// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit
import Observation

/// Sending a Hum file straight to a nearby device (Share & sync → Send / Receive).
///
/// Only the local network and Wi-Fi between devices, no internet and no servers. A parent opens
/// Receive on one device and Send on the other. The receiver can only be found while its Receive screen
/// is open, sees who is sending and a code that must match the sender's, and must tap Accept. The file
/// then goes through the normal import preview, like a file from AirDrop: nothing changes until the
/// parent chooses Merge or Replace.
///
/// `NearbyTransfer` holds the steps, `NearbyLink` the encrypted conversation (`NearbyProtocol.swift`),
/// and a `NearbyTransport` finds devices and carries bytes (Network framework in the app, a fake in tests).
@MainActor
@Observable
final class NearbyTransfer {
    enum Role { case send, receive }

    enum State: Equatable {
        /// Not started, or stopped.
        case idle
        /// Sender: listing nearby devices. Receiver: waiting to be found.
        case looking
        /// Sender: reaching the chosen device.
        case connecting(NearbyPeer)
        /// Sender: the other device is asking its parent. Both screens show `code`.
        case waitingForAnswer(NearbyPeer, code: String)
        /// Receiver: someone wants to send a file. Accept or Decline.
        case asking(NearbyOffer, code: String)
        /// Sending or receiving, 0…1.
        case transferring(Double)
        /// Sender: the other device has the whole file.
        case sent
        /// Receiver: the file arrived and its import preview is open.
        case received
        /// Sender: the other device said no.
        case declined
        case failed(NearbyTransferError)
    }

    let role: Role
    private(set) var state: State = .idle
    /// Sender: devices with their Receive screen open.
    private(set) var peers: [NearbyPeer] = []
    /// This device's name, as other devices see it.
    var localName: String { transport.localName }
    /// Receiver: a device that connects but makes no offer in this time is let go.
    var offerTimeout: Duration = .seconds(20)

    private let transport: NearbyTransport
    /// Receiver: hands the received bytes to the import preview.
    private let deliver: (Data, String) -> Void
    /// Sender: the file to send, once it's made.
    private var file: (data: Data, name: String)?
    private var link: NearbyLink?
    private var code: String?
    private var offer: NearbyOffer?
    private var incoming = Data()
    private var sentBytes = 0

    init(role: Role, transport: NearbyTransport, deliver: @escaping (Data, String) -> Void = { _, _ in }) {
        self.role = role
        self.transport = transport
        self.deliver = deliver
        transport.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// Starts being found (receiver) or looking (sender).
    func start() {
        guard state == .idle else { return }
        state = .looking
        switch role {
        case .send: transport.browse()
        case .receive: transport.advertise()
        }
    }

    /// Stops everything. Called when the screen closes: the device can't be found after this.
    func stop() {
        dropLink(tellingOtherSide: true)
        transport.stop()
        peers = []
        incoming = Data()
        state = .idle
    }

    // MARK: Sender

    var hasFile: Bool { file != nil }

    /// The made `.hum` file. Sending is possible once this is set.
    func setFile(_ data: Data, name: String) throws {
        guard !data.isEmpty else { throw NearbyTransferError.unreadable }
        guard data.count <= NearbyOffer.maxFileBytes else { throw NearbyTransferError.tooBig }
        file = (data, NearbyOffer.safeFileName(name))
    }

    /// Reaches `peer`, then asks it to accept the file.
    func send(to peer: NearbyPeer) {
        guard role == .send, file != nil else { return }
        switch state {
        case .looking, .declined, .sent, .failed: break
        default: return
        }
        dropLink(tellingOtherSide: false)
        state = .connecting(peer)
        open(NearbyLink(channel: transport.connect(to: peer), isSender: true))
    }

    /// Stops waiting or sending, and goes back to the list of devices (sender), or to waiting (receiver).
    func cancel() {
        dropLink(tellingOtherSide: true)
        incoming = Data()
        state = .looking
    }

    // MARK: Receiver

    func accept() {
        guard role == .receive, case .asking = state, let link else { return }
        incoming = Data()
        state = .transferring(0)
        link.send(.accept)
    }

    func decline() {
        guard role == .receive, case .asking = state, let link else { return }
        self.link = nil
        link.send(.decline) { _ in link.close() }
        state = .looking
    }

    // MARK: Events

    private func handle(_ event: NearbyTransportEvent) {
        switch event {
        case .peers(let found):
            guard role == .send else { return }
            peers = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        case .incoming(let channel):
            // One sender at a time, and only while waiting.
            guard role == .receive, link == nil, state == .looking || isFailed else {
                channel.close()
                return
            }
            let link = NearbyLink(channel: channel, isSender: false)
            open(link)
            // A device that connects but never makes an offer doesn't keep this one busy.
            let timeout = offerTimeout
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, self.link === link, self.offer == nil else { return }
                self.dropLink(tellingOtherSide: false)
            }

        case .failed(let error):
            if state == .looking { state = .failed(error) }
        }
    }

    private var isFailed: Bool {
        if case .failed = state { true } else { false }
    }

    private func open(_ link: NearbyLink) {
        self.link = link
        code = nil
        offer = nil
        link.onEvent = { [weak self, weak link] event in
            guard let self, let link, self.link === link else { return }
            switch self.role {
            case .send: self.senderHandle(event)
            case .receive: self.receiverHandle(event)
            }
        }
        link.start()
    }

    private func senderHandle(_ event: NearbyLink.Event) {
        switch event {
        case .secured(let code):
            guard case .connecting(let peer) = state, let file, let link else { return }
            let offer = NearbyOffer(fileName: file.name, byteCount: file.data.count, senderName: transport.localName)
            self.offer = offer
            state = .waitingForAnswer(peer, code: code)
            link.send(.offer(offer))

        case .message(.accept):
            guard case .waitingForAnswer = state else { return failLink(.badData) }
            sentBytes = 0
            state = .transferring(0)
            sendNextChunk()

        case .message(.decline):
            guard case .waitingForAnswer = state else { return failLink(.badData) }
            dropLink(tellingOtherSide: false)
            state = .declined

        case .message(.gotIt):
            guard case .transferring = state, sentBytes == file?.data.count else { return failLink(.badData) }
            dropLink(tellingOtherSide: false)
            state = .sent

        case .message(.cancel):
            if case .waitingForAnswer = state {
                dropLink(tellingOtherSide: false)
                state = .declined
            } else {
                failLink(.stopped)
            }

        case .message:
            failLink(.badData)

        case .closed(let error):
            switch state {
            case .connecting: failLink(.couldNotConnect)
            case .waitingForAnswer, .transferring: failLink(error ?? .lostConnection)
            default: dropLink(tellingOtherSide: false)
            }
        }
    }

    /// One piece at a time, the next once the last has gone, so a big file isn't held twice in memory.
    private func sendNextChunk() {
        guard case .transferring = state, let file, let link else { return }
        let total = file.data.count
        guard sentBytes < total else {
            link.send(.done(digest: Data(SHA256.hash(data: file.data))))
            return
        }
        let end = min(sentBytes + NearbyMessage.chunkBytes, total)
        let chunk = file.data.subdata(in: sentBytes..<end)
        link.send(.chunk(chunk)) { [weak self, weak link] ok in
            guard let self, let link, self.link === link else { return }
            guard ok else { return self.failLink(.lostConnection) }
            self.sentBytes = end
            self.state = .transferring(Double(end) / Double(total))
            self.sendNextChunk()
        }
    }

    private func receiverHandle(_ event: NearbyLink.Event) {
        switch event {
        case .secured(let code):
            self.code = code

        case .message(.offer(let offer)):
            guard state == .looking || isFailed, self.offer == nil, let code else { return failLink(.badData) }
            self.offer = offer
            state = .asking(offer, code: code)

        case .message(.chunk(let bytes)):
            guard case .transferring = state, let offer, incoming.count + bytes.count <= offer.byteCount else {
                return failLink(.unreadable)
            }
            incoming.append(bytes)
            state = .transferring(Double(incoming.count) / Double(offer.byteCount))

        case .message(.done(let digest)):
            guard case .transferring = state, let offer, let link, incoming.count == offer.byteCount,
                  Data(SHA256.hash(data: incoming)) == digest else {
                return failLink(.unreadable)
            }
            let data = incoming
            incoming = Data()
            self.link = nil
            link.send(.gotIt) { _ in link.close() }
            // Done with other devices: stop being found before the preview opens.
            transport.stop()
            state = .received
            deliver(data, offer.fileName)

        case .message(.cancel):
            if case .transferring = state {
                failLink(.stopped)
            } else {
                // The sender gave up before this device answered.
                dropLink(tellingOtherSide: false)
                state = .looking
            }

        case .message:
            failLink(.badData)

        case .closed(let error):
            if case .transferring = state {
                failLink(error ?? .lostConnection)
            } else {
                dropLink(tellingOtherSide: false)
                if case .asking = state { state = .looking }
            }
        }
    }

    private func failLink(_ error: NearbyTransferError) {
        dropLink(tellingOtherSide: true)
        incoming = Data()
        state = .failed(error)
    }

    private func dropLink(tellingOtherSide: Bool) {
        guard let link else { return }
        self.link = nil
        offer = nil
        code = nil
        if tellingOtherSide {
            link.send(.cancel) { _ in link.close() }
        } else {
            link.close()
        }
    }
}

/// An encrypted conversation with one device over a channel: the handshake, then sealed messages.
@MainActor
final class NearbyLink {
    enum Event {
        /// The handshake is done; `code` is shown on both screens.
        case secured(code: String)
        case message(NearbyMessage)
        /// The connection ended (`nil`: closed normally by the other side).
        case closed(NearbyTransferError?)
    }

    var onEvent: ((Event) -> Void)?

    private let channel: NearbyChannel
    private let isSender: Bool
    private let handshake: NearbyHandshake
    private var frames = NearbyFrames()
    private var senderHello: Data?
    private var keys: NearbyKeys?
    private var isClosed = false

    init(channel: NearbyChannel, isSender: Bool) {
        self.channel = channel
        self.isSender = isSender
        handshake = NearbyHandshake(isSender: isSender)
    }

    func start() {
        channel.onEvent = { [weak self] event in self?.handle(event) }
        channel.start()
    }

    func send(_ message: NearbyMessage, completion: ((Bool) -> Void)? = nil) {
        guard !isClosed, var keys, let sealed = try? keys.sealer.seal(message.encoded()) else {
            completion?(false)
            return
        }
        self.keys = keys
        channel.send(NearbyFrames.frame(sealed)) { ok in completion?(ok) }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        onEvent = nil
        channel.close()
    }

    private func handle(_ event: NearbyChannelEvent) {
        guard !isClosed else { return }
        switch event {
        case .ready:
            if isSender { sendPlain(handshake.hello()) }
        case .received(let bytes):
            do {
                for frame in try frames.append(bytes) {
                    try handleFrame(frame)
                    if isClosed { return }
                }
            } catch {
                fail(error as? NearbyTransferError ?? .badData)
            }
        case .closed:
            fail(nil)
        }
    }

    private func handleFrame(_ frame: Data) throws {
        if var keys {
            let plain = try keys.opener.open(frame)
            self.keys = keys
            onEvent?(.message(try NearbyMessage.decode(plain)))
        } else if isSender {
            let (reveal, keys) = try handshake.finishAsSender(receiverHello: frame)
            sendPlain(reveal)
            self.keys = keys
            onEvent?(.secured(code: keys.code))
        } else if let senderHello {
            let keys = try handshake.finishAsReceiver(senderHello: senderHello, reveal: frame)
            self.keys = keys
            onEvent?(.secured(code: keys.code))
        } else {
            guard frame.count == NearbyHandshake.helloBytes else { throw NearbyTransferError.badData }
            senderHello = frame
            sendPlain(handshake.hello())
        }
    }

    private func sendPlain(_ data: Data) {
        channel.send(NearbyFrames.frame(data)) { _ in }
    }

    private func fail(_ error: NearbyTransferError?) {
        guard !isClosed else { return }
        let onEvent = self.onEvent
        close()
        onEvent?(.closed(error))
    }
}

/// A nearby device running Hum with its Receive screen open.
nonisolated struct NearbyPeer: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

enum NearbyTransportEvent {
    /// Sender: everyone found right now.
    case peers([NearbyPeer])
    /// Receiver: a sender connected.
    case incoming(NearbyChannel)
    /// Couldn't start looking or being found.
    case failed(NearbyTransferError)
}

/// Finds devices and connects to them. Every call and event is on the main actor.
@MainActor
protocol NearbyTransport: AnyObject {
    var onEvent: ((NearbyTransportEvent) -> Void)? { get set }
    var localName: String { get }
    /// Receiver: be findable by name.
    func advertise()
    /// Sender: look for receivers.
    func browse()
    func connect(to peer: NearbyPeer) -> NearbyChannel
    /// Stops advertising and browsing. Open channels close themselves.
    func stop()
}

enum NearbyChannelEvent {
    case ready
    case received(Data)
    case closed
}

/// A two-way, in-order byte stream to one device.
@MainActor
protocol NearbyChannel: AnyObject {
    var onEvent: ((NearbyChannelEvent) -> Void)? { get set }
    func start()
    func send(_ data: Data, completion: @escaping (Bool) -> Void)
    func close()
}

nonisolated enum NearbyTransferError: Error, Equatable, Sendable {
    /// The other side sent something that isn't Hum's, or that was changed on the way.
    case badData
    case tooBig
    /// The file didn't arrive whole.
    case unreadable
    case lostConnection
    /// The other device stopped the transfer.
    case stopped
    /// Couldn't start (Wi-Fi off, or local network access turned off for Hum).
    case couldNotConnect

    var message: String {
        switch self {
        case .badData: String(localized: "The other device sent something Hum can't read. Make sure both devices have the latest Hum, then try again.")
        case .tooBig: String(localized: "These boards are too big to send this way. Use “Send with AirDrop” instead.")
        case .unreadable: String(localized: "The file didn't arrive in one piece. Try again.")
        case .lostConnection: String(localized: "The connection was lost. Keep both devices close together and try again.")
        case .stopped: String(localized: "The other device stopped.")
        case .couldNotConnect: String(localized: "Hum couldn't reach nearby devices. Check that Wi-Fi is on, and that Hum is allowed to use the local network in Settings.")
        }
    }
}
