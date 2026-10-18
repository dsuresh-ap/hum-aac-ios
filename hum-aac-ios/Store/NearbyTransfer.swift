// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit
import Observation

/// Sending a Hum file straight to a nearby device (Share & sync → Send / Receive).
///
/// Only the local network and Wi-Fi between devices, no internet and no servers. A parent opens
/// Receive on one device and Send on the other, then picks the device. The receiving screen shows a
/// six-digit code, and the parent types it on the sending device: nothing about the file leaves the sender
/// until the code matches, so a look-alike device that answers first gets nothing. Then the receiver sees
/// what is coming and taps Accept, and the file goes through the normal import preview, like a file from
/// AirDrop: nothing changes until the parent chooses Merge or Replace.
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
        /// Sender: connected; the parent types the code the other device shows.
        case confirming(NearbyPeer)
        /// Sender: the code matched; the other device is asking its parent.
        case waitingForAnswer(NearbyPeer)
        /// Receiver: a device connected. Shows the code to type on the sending device.
        case pairing(code: String)
        /// Receiver: the sender typed the right code and wants to send this file. Accept or Decline.
        case asking(NearbyOffer)
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
    private(set) var state: State = .idle {
        didSet { if state != oldValue { phaseStarted = .now } }
    }
    /// Sender: devices with their Receive screen open.
    private(set) var peers: [NearbyPeer] = []
    /// Sender: the last code typed didn't match.
    private(set) var codeWasWrong = false
    /// This device's name, as other devices see it.
    var localName: String { transport.localName }

    /// While bytes should be flowing (connecting, the handshake, the file): give up after this long
    /// without any.
    var idleTimeout: Duration = .seconds(30)
    /// While a person is reading or typing a code, or deciding: give up after this long.
    var personTimeout: Duration = .seconds(120)
    /// Receiver: after a sender is turned away or gives up, other devices wait this long before the
    /// next try, so nobody can fill the screen with prompts.
    var cooldown: Duration = .seconds(2)

    private let transport: NearbyTransport
    /// Receiver: hands the received bytes to the import preview.
    private let deliver: (Data, String) -> Void
    /// Sender: the file to send, once it's made.
    private var file: (data: Data, name: String, digest: Data)?
    private var link: NearbyLink?
    private var code: String?
    private var offer: NearbyOffer?
    private var incoming: IncomingFile?
    private var sentBytes = 0
    private var phaseStarted = ContinuousClock.now
    private var lastActivity = ContinuousClock.now
    private var quietUntil = ContinuousClock.now

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
        state = .idle
    }

    // MARK: Sender

    var hasFile: Bool { file != nil }

    /// The made `.hum` file. Sending is possible once this is set.
    func setFile(_ data: Data, name: String) throws {
        guard !data.isEmpty else { throw NearbyTransferError.unreadable }
        guard data.count <= NearbyOffer.maxFileBytes else { throw NearbyTransferError.tooBig }
        file = (data, NearbyOffer.safeFileName(name), Data(SHA256.hash(data: data)))
    }

    /// Reaches `peer`. Nothing is sent until the parent types the code it shows (`confirm`).
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

    /// The code the parent read on the other device. Only when it matches does the sender say what it
    /// wants to send. A wrong code can be typed again; the other device's code doesn't change.
    @discardableResult
    func confirm(code typed: String) -> Bool {
        guard role == .send, case .confirming(let peer) = state, let code, let file, let link else { return false }
        guard typed.filter(\.isNumber) == code else {
            codeWasWrong = true
            return false
        }
        codeWasWrong = false
        let offer = NearbyOffer(fileName: file.name, byteCount: file.data.count, senderName: transport.localName)
        self.offer = offer
        state = .waitingForAnswer(peer)
        link.send(.offer(offer))
        return true
    }

    /// Stops waiting or sending, and goes back to the list of devices (sender), or to waiting (receiver).
    func cancel() {
        dropLink(tellingOtherSide: true)
        state = .looking
    }

    // MARK: Receiver

    func accept() {
        guard role == .receive, case .asking(let offer) = state, let link else { return }
        do {
            incoming = try IncomingFile(expected: offer.byteCount)
        } catch {
            return failLink(.unreadable)
        }
        state = .transferring(0)
        link.send(.accept)
    }

    func decline() {
        guard role == .receive, case .asking = state, let link else { return }
        self.link = nil
        link.send(.decline) { _ in link.close() }
        backToWaiting()
    }

    // MARK: Events

    private func handle(_ event: NearbyTransportEvent) {
        switch event {
        case .peers(let found):
            guard role == .send else { return }
            peers = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        case .incoming(let channel):
            // One sender at a time, only while waiting, and not straight after the last one.
            guard role == .receive, link == nil, state == .looking || isFailed, ContinuousClock.now >= quietUntil else {
                channel.close()
                return
            }
            open(NearbyLink(channel: channel, isSender: false))

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
        lastActivity = .now
        link.onEvent = { [weak self, weak link] event in
            guard let self, let link, self.link === link else { return }
            self.lastActivity = .now
            switch self.role {
            case .send: self.senderHandle(event)
            case .receive: self.receiverHandle(event)
            }
        }
        link.start()
        watch(link)
    }

    /// Gives up on a link that has gone quiet, or a person who walked away.
    private func watch(_ link: NearbyLink) {
        let tick = min(idleTimeout, personTimeout, .seconds(1)) / 4
        Task { [weak self, weak link] in
            while true {
                try? await Task.sleep(for: tick)
                guard let self, let link, self.link === link else { return }
                self.checkTimeouts(link)
            }
        }
    }

    private func checkTimeouts(_ link: NearbyLink) {
        let now = ContinuousClock.now
        let waitingForPerson: Bool
        switch state {
        case .confirming, .waitingForAnswer, .pairing, .asking: waitingForPerson = true
        default: waitingForPerson = false
        }
        if waitingForPerson {
            guard now - phaseStarted > personTimeout else { return }
            if role == .receive { return walkAway() }
            failLink(.timedOut)
        } else {
            guard now - max(lastActivity, link.lastActivity) > idleTimeout else { return }
            switch state {
            case .connecting: failLink(.couldNotConnect)
            case .transferring: failLink(.lostConnection)
            default: dropLink(tellingOtherSide: false)  // receiver: connected but never finished the handshake
            }
        }
    }

    /// Receiver: nobody answered (or the sender never typed the code): wait for a sender again.
    private func walkAway() {
        dropLink(tellingOtherSide: true)
        backToWaiting()
    }

    private func senderHandle(_ event: NearbyLink.Event) {
        switch event {
        case .secured(let code):
            guard case .connecting(let peer) = state else { return }
            self.code = code
            codeWasWrong = false
            state = .confirming(peer)

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
            switch state {
            case .confirming, .waitingForAnswer:
                dropLink(tellingOtherSide: false)
                state = .declined
            default:
                failLink(.stopped)
            }

        case .message:
            failLink(.badData)

        case .closed(let error):
            switch state {
            case .connecting: failLink(.couldNotConnect)
            case .confirming, .waitingForAnswer, .transferring: failLink(error ?? .lostConnection)
            default: dropLink(tellingOtherSide: false)
            }
        }
    }

    /// One piece at a time, the next once the last has gone, so a big file isn't held twice in memory.
    private func sendNextChunk() {
        guard case .transferring = state, let file, let link else { return }
        let total = file.data.count
        guard sentBytes < total else {
            link.send(.done(digest: file.digest))
            return
        }
        let end = min(sentBytes + NearbyMessage.chunkBytes, total)
        let chunk = file.data.subdata(in: sentBytes..<end)
        link.send(.chunk(chunk)) { [weak self, weak link] ok in
            guard let self, let link, self.link === link else { return }
            guard ok else { return self.failLink(.lostConnection) }
            self.lastActivity = .now
            self.sentBytes = end
            self.state = .transferring(Double(end) / Double(total))
            self.sendNextChunk()
        }
    }

    private func receiverHandle(_ event: NearbyLink.Event) {
        switch event {
        case .secured(let code):
            guard state == .looking || isFailed else { return failLink(.badData) }
            self.code = code
            state = .pairing(code: code)

        case .message(.offer(let offer)):
            // Only after the sender typed the code shown here.
            guard case .pairing = state, self.offer == nil else { return failLink(.badData) }
            self.offer = offer
            state = .asking(offer)

        case .message(.chunk(let bytes)):
            guard case .transferring = state, let incoming else { return failLink(.unreadable) }
            do {
                try incoming.append(bytes)
            } catch {
                return failLink(.unreadable)
            }
            state = .transferring(incoming.fraction)

        case .message(.done(let digest)):
            guard case .transferring = state, let offer, let link, let incoming,
                  let data = try? incoming.finish(digest: digest) else {
                return failLink(.unreadable)
            }
            self.incoming = nil
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
                backToWaiting()
            }

        case .message:
            failLink(.badData)

        case .closed(let error):
            if case .transferring = state {
                failLink(error ?? .lostConnection)
            } else {
                dropLink(tellingOtherSide: false)
                switch state {
                case .pairing, .asking: backToWaiting()
                default: break
                }
            }
        }
    }

    /// Receiver: wait for a sender again, after a short quiet time.
    private func backToWaiting() {
        quietUntil = .now + cooldown
        state = .looking
    }

    private func failLink(_ error: NearbyTransferError) {
        dropLink(tellingOtherSide: true)
        if role == .receive { quietUntil = .now + cooldown }
        state = .failed(error)
    }

    private func dropLink(tellingOtherSide: Bool) {
        incoming?.discard()
        incoming = nil
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

/// Receiver: the file as it arrives, written to a temporary file instead of held in memory, and checked
/// against the size and SHA-256 the sender promised.
@MainActor
final class IncomingFile {
    private let url: URL
    private let handle: FileHandle
    private let expected: Int
    private var hasher = SHA256()
    private var count = 0

    init(expected: Int) throws {
        self.expected = expected
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Nearby-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("received.hum")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw NearbyTransferError.unreadable }
        handle = try FileHandle(forWritingTo: url)
    }

    var fraction: Double { Double(count) / Double(expected) }

    func append(_ bytes: Data) throws {
        guard count + bytes.count <= expected else { throw NearbyTransferError.unreadable }
        try handle.write(contentsOf: bytes)
        hasher.update(data: bytes)
        count += bytes.count
    }

    /// The whole file, mapped from disk, if it is all there and unchanged. The temporary file is deleted
    /// either way (the mapped bytes stay readable).
    func finish(digest: Data) throws -> Data {
        defer { discard() }
        try handle.close()
        guard count == expected, Data(hasher.finalize()) == digest else { throw NearbyTransferError.unreadable }
        return try Data(contentsOf: url, options: .alwaysMapped)
    }

    func discard() {
        try? handle.close()
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

/// An encrypted conversation with one device over a channel: the handshake, then sealed messages.
@MainActor
final class NearbyLink {
    enum Event {
        /// The handshake is done. The receiver shows `code`; the sender checks what the parent types.
        case secured(code: String)
        case message(NearbyMessage)
        /// The connection ended (`nil`: closed normally by the other side).
        case closed(NearbyTransferError?)
    }

    var onEvent: ((Event) -> Void)?
    /// When bytes last arrived (the handshake sends no events of its own).
    private(set) var lastActivity = ContinuousClock.now

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
            lastActivity = .now
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
    /// Nobody typed the code or answered in time.
    case timedOut

    var message: String {
        switch self {
        case .badData: String(localized: "The other device sent something Hum can't read. Make sure both devices have the latest Hum, then try again.")
        case .tooBig: String(localized: "These boards are too big to send this way. Use “Send with AirDrop” instead.")
        case .unreadable: String(localized: "The file didn't arrive in one piece. Try again.")
        case .lostConnection: String(localized: "The connection was lost. Keep both devices close together and try again.")
        case .stopped: String(localized: "The other device stopped.")
        case .couldNotConnect: String(localized: "Hum couldn't reach nearby devices. Check that Wi-Fi is on, and that Hum is allowed to use the local network in Settings.")
        case .timedOut: String(localized: "Nothing happened for a while, so Hum stopped. Try again when both devices are ready.")
        }
    }
}
