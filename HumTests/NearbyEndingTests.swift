// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
import Testing
@testable import Hum

/// A device that knows Hum's protocol but sends whatever a test says, whenever: a broken or hostile
/// sender or receiver.
@MainActor
final class RogueLink {
    let link: NearbyLink
    /// The codes from the handshake, once it's done.
    private(set) var code: String?
    private(set) var messages: [NearbyMessage] = []
    private(set) var closed = false

    init(channel: NearbyChannel, isSender: Bool) {
        link = NearbyLink(channel: channel, isSender: isSender)
        link.onEvent = { [unowned self] event in
            switch event {
            case .secured(let code, _): self.code = code
            case .message(let message): self.messages.append(message)
            case .closed: self.closed = true
            }
        }
        link.start()
    }

    func send(_ message: NearbyMessage) { link.send(message) }
}

/// How nearby transfers end when the other side breaks the rules, the network fails, or the parent does
/// things out of turn. Every one of them ends calmly, says why, and leaves nothing behind.
@MainActor
@Suite("Nearby transfer: endings")
struct NearbyEndingTests {
    let flow = NearbyTransferTests()

    /// A rogue sender that has done the handshake with the real receiver, which now shows its code.
    func rogueSender(_ pair: NearbyTransferTests.Pair) throws -> (RogueLink, FakeChannel) {
        let peer = try #require(pair.sender.peers.first)
        let channel = try #require(pair.senderTransport.connect(to: peer) as? FakeChannel)
        let rogue = RogueLink(channel: channel, isSender: true)
        pair.network.run()
        #expect({ if case .pairing = pair.receiver.state { true } else { false } }())
        return (rogue, channel)
    }

    /// A rogue receiver the real sender has connected to; the sender now waits for its code.
    func rogueReceiver(_ pair: NearbyTransferTests.Pair) throws -> RogueLink {
        final class Box { var rogue: RogueLink? }
        let box = Box()
        let stranger = FakeTransport(name: "Stranger", network: pair.network)
        stranger.onEvent = { event in
            if case .incoming(let channel) = event { box.rogue = RogueLink(channel: channel, isSender: false) }
        }
        stranger.advertise()
        pair.network.run()
        try pair.sender.setFile(Data(count: 1_000_000), name: "x.hum")
        pair.sender.send(to: try #require(pair.sender.peers.first { $0.name == "Stranger" }))
        pair.network.run()
        #expect({ if case .confirming = pair.sender.state { true } else { false } }())
        return try #require(box.rogue)
    }

    func offer(byteCount: Int = 100) -> NearbyOffer {
        NearbyOffer(fileName: "x.hum", byteCount: byteCount, senderName: "Stranger")
    }

    // MARK: A sender that breaks the rules

    @Test func aFileBeforeAcceptIsRefused() throws {
        let pair = flow.makePair { _, _ in }
        let (rogue, _) = try rogueSender(pair)
        rogue.send(.chunk(Data([1, 2, 3])))
        pair.network.run()
        #expect(pair.receiver.state == .failed(.unreadable))
        #expect(!pair.receiverTransport.isAdvertising, "stops listening until the parent starts again")
        #expect(rogue.messages == [.cancel(.error)], "the other side hears that it stopped")
    }

    @Test(arguments: [NearbyMessage.accept, .decline, .gotIt])
    func whatOnlyAReceiverSaysIsRefused(message: NearbyMessage) throws {
        let pair = flow.makePair { _, _ in }
        let (rogue, _) = try rogueSender(pair)
        rogue.send(message)
        pair.network.run()
        #expect(pair.receiver.state == .failed(.badData))
    }

    @Test func aSecondOfferIsRefused() throws {
        let pair = flow.makePair { _, _ in }
        let (rogue, _) = try rogueSender(pair)
        rogue.send(.offer(offer()))
        pair.network.run()
        #expect(pair.receiver.state == .asking(offer()))
        rogue.send(.offer(offer(byteCount: 200)))
        pair.network.run()
        #expect(pair.receiver.state == .failed(.badData))
    }

    @Test func doneBeforeAcceptIsRefused() throws {
        let pair = flow.makePair { _, _ in }
        let (rogue, _) = try rogueSender(pair)
        rogue.send(.offer(offer()))
        rogue.send(.done(digest: Data(count: 32)))
        pair.network.run()
        #expect(pair.receiver.state == .failed(.unreadable))
    }

    @Test func anOfferTooBigToTakeSaysSo() throws {
        let pair = flow.makePair { _, _ in }
        let (rogue, _) = try rogueSender(pair)
        rogue.send(.offer(offer(byteCount: NearbyOffer.maxFileBytes + 1)))
        pair.network.run()
        #expect(pair.receiver.state == .failed(.tooBig))
    }

    @Test(arguments: [(NearbyStopReason.error, NearbyTransferError.stopped), (.cancelled, .otherCancelled),
                      (.timedOut, .otherTimedOut), (.leftFront, .otherLeftFront)])
    func aStopFromTheSenderSaysWhy(reason: NearbyStopReason, shown: NearbyTransferError) throws {
        let pair = flow.makePair { _, _ in }
        let (rogue, _) = try rogueSender(pair)
        rogue.send(.cancel(reason))
        pair.network.run()
        #expect(pair.receiver.state == .failed(shown))
        #expect(!pair.receiverTransport.isAdvertising)
    }

    // MARK: Broken frames

    /// Something that isn't Hum connects: it's let go, and the receiver keeps waiting for a real sender.
    @Test func aBrokenHelloKeepsTheReceiverListening() throws {
        let pair = flow.makePair { _, _ in }
        let peer = try #require(pair.sender.peers.first)
        let channel = try #require(pair.senderTransport.connect(to: peer) as? FakeChannel)
        channel.start()
        pair.network.run()
        channel.send(NearbyFrames.frame(Data("HUM1".utf8))) { _ in }
        pair.network.run()
        #expect(channel.closed, "let go")
        #expect(pair.receiver.state == .looking)
        #expect(pair.receiverTransport.isAdvertising)
        try flow.offer(pair, file: Data(count: 100))
        #expect({ if case .asking = pair.receiver.state { true } else { false } }(), "a real sender still gets through")
    }

    @Test func aKeyThatDoesntMatchItsHashIsLetGo() throws {
        let pair = flow.makePair { _, _ in }
        let peer = try #require(pair.sender.peers.first)
        let channel = try #require(pair.senderTransport.connect(to: peer) as? FakeChannel)
        channel.start()
        pair.network.run()
        channel.send(NearbyFrames.frame(NearbyHandshake.magic + Data(count: 32))) { _ in }
        pair.network.run()
        channel.send(NearbyFrames.frame(Data(repeating: 9, count: 32))) { _ in }  // not the key that was promised
        pair.network.run()
        #expect(channel.closed)
        #expect(pair.receiver.state == .looking)
    }

    @Test func aFrameTooBigToBeHumsEndsTheTry() throws {
        let pair = flow.makePair { _, _ in }
        let (_, channel) = try rogueSender(pair)
        let tooBig = UInt32(NearbyFrames.maxFrameBytes + 1)
        channel.send(Data([UInt8(tooBig >> 24), UInt8(tooBig >> 16 & 0xFF), UInt8(tooBig >> 8 & 0xFF), UInt8(tooBig & 0xFF)])) { _ in }
        pair.network.run()
        #expect(pair.receiver.state == .failed(.badData))
    }

    @Test func aFrameSentTwiceIsRefused() throws {
        let pair = flow.makePair { _, _ in }
        let (rogue, channel) = try rogueSender(pair)
        channel.tamper = { $0 + $0 }
        rogue.send(.offer(offer()))
        pair.network.run()
        #expect(pair.receiver.state == .failed(.badData))
    }

    // MARK: A receiver that breaks the rules

    @Test func anAnswerBeforeTheCodeIsRefused() throws {
        let pair = flow.makePair { _, _ in }
        let rogue = try rogueReceiver(pair)
        rogue.send(.accept)
        pair.network.run()
        #expect(pair.sender.state == .failed(.badData))
        #expect(rogue.messages == [.cancel(.error)])
    }

    @Test(arguments: [NearbyMessage.gotIt, .offer(NearbyOffer(fileName: "x.hum", byteCount: 1, senderName: "x")),
                      .chunk(Data([1])), .done(digest: Data(count: 32))])
    func whatTheReceiverMayNotSayYetIsRefused(message: NearbyMessage) throws {
        let pair = flow.makePair { _, _ in }
        let rogue = try rogueReceiver(pair)
        pair.sender.confirm(code: try #require(rogue.code))
        pair.network.run()
        #expect(rogue.messages.count == 1, "the offer, once the code matched")
        rogue.send(message)
        pair.network.run()
        #expect(pair.sender.state == .failed(.badData))
    }

    @Test func gotItHalfwayIsRefused() throws {
        let pair = flow.makePair { _, _ in }
        let rogue = try rogueReceiver(pair)
        pair.sender.confirm(code: try #require(rogue.code))
        pair.network.run()
        rogue.send(.accept)
        pair.network.run(limit: 4)
        rogue.send(.gotIt)
        pair.network.run()
        #expect(pair.sender.state == .failed(.badData))
    }

    @Test func declineAfterAcceptIsRefused() throws {
        let pair = flow.makePair { _, _ in }
        let rogue = try rogueReceiver(pair)
        pair.sender.confirm(code: try #require(rogue.code))
        pair.network.run()
        rogue.send(.accept)
        rogue.send(.decline)
        pair.network.run()
        #expect(pair.sender.state == .failed(.badData))
    }

    @Test func aStopFromTheReceiverSaysWhy() throws {
        let pair = flow.makePair { _, _ in }
        let rogue = try rogueReceiver(pair)
        pair.sender.confirm(code: try #require(rogue.code))
        pair.network.run()
        rogue.send(.cancel(.timedOut))
        pair.network.run()
        #expect(pair.sender.state == .failed(.otherTimedOut))
    }

    @Test func aReceiverThatHangsUpWhileTheCodeIsTyped() throws {
        let pair = flow.makePair { _, _ in }
        let rogue = try rogueReceiver(pair)
        rogue.link.close()
        pair.network.run()
        #expect(pair.sender.state == .failed(.lostConnection))
    }

    @Test func aReceiverThatIsntHumCantBeReached() throws {
        let pair = flow.makePair { _, _ in }
        let stranger = FakeTransport(name: "Stranger", network: pair.network)
        stranger.onEvent = { event in
            guard case .incoming(let channel) = event else { return }
            // Answers the hello with something that isn't Hum's.
            channel.onEvent = { if case .received = $0 { channel.send(NearbyFrames.frame(Data(count: NearbyHandshake.helloBytes))) { _ in } } }
            channel.start()
        }
        stranger.advertise()
        pair.network.run()
        try pair.sender.setFile(Data(count: 100), name: "x.hum")
        pair.sender.send(to: try #require(pair.sender.peers.first { $0.name == "Stranger" }))
        pair.network.run()
        #expect(pair.sender.state == .failed(.couldNotConnect))
    }

    // MARK: The network, and the parent out of turn

    @Test func aReceiverThatCantBeFoundSaysSo() {
        let pair = flow.makePair { _, _ in }
        pair.receiverTransport.onEvent?(.failed(.couldNotConnect))
        #expect(pair.receiver.state == .failed(.couldNotConnect))
        #expect(!pair.receiverTransport.isAdvertising)
        pair.senderTransport.onEvent?(.failed(.couldNotConnect))
        #expect(pair.sender.state == .failed(.couldNotConnect))
        // Starting again works once the network is back.
        pair.receiver.restart()
        #expect(pair.receiver.state == .looking && pair.receiverTransport.isAdvertising)
    }

    @Test func aNetworkProblemMidTryIsLeftToTheConnection() throws {
        let pair = flow.makePair { _, _ in }
        try flow.offer(pair, file: Data(count: 100))
        pair.receiverTransport.onEvent?(.failed(.couldNotConnect))
        #expect({ if case .asking = pair.receiver.state { true } else { false } }())
    }

    @Test func aSenderTakesNoIncomingConnections() {
        let pair = flow.makePair { _, _ in }
        let mine = FakeChannel(network: pair.network)
        let theirs = FakeChannel(network: pair.network)
        mine.other = theirs
        theirs.other = mine
        pair.senderTransport.onEvent?(.incoming(theirs))
        #expect(theirs.closed)
        #expect(pair.sender.state == .looking)
        pair.receiverTransport.onEvent?(.peers([NearbyPeer(id: "x", name: "x")]))
        #expect(pair.receiver.state == .looking, "a receiver doesn't list devices")
    }

    @Test func nothingHappensOutOfTurn() throws {
        let pair = flow.makePair { _, _ in }
        let peer = try #require(pair.sender.peers.first)
        // No file yet: nothing to send.
        pair.sender.send(to: peer)
        #expect(pair.sender.state == .looking && pair.senderTransport.channels.isEmpty)
        // Not a receiver's job, and nothing to answer yet.
        pair.receiver.send(to: peer)
        #expect(!pair.sender.confirm(code: "123456"))
        #expect(!pair.receiver.accept(code: "123456"))
        pair.receiver.decline()
        #expect(pair.receiver.state == .looking)
        pair.receiver.start()
        pair.sender.leave()
        #expect(pair.sender.state == .looking, "plain looking isn't stopped by leaving the front")

        // Busy typing a code: a second Send is ignored.
        try pair.sender.setFile(Data(count: 100), name: "x.hum")
        pair.sender.send(to: peer)
        pair.network.run()
        pair.sender.send(to: peer)
        #expect(pair.senderTransport.channels.count == 1)
        #expect(!pair.receiver.accept(code: "123456"), "nothing offered yet")
    }

    @Test func aFileThatCantBeSentSaysWhy() {
        let pair = flow.makePair { _, _ in }
        #expect(throws: NearbyTransferError.unreadable) { try pair.sender.setFile(Data(), name: "x.hum") }
        #expect(throws: NearbyTransferError.tooBig) { try pair.sender.setFile(Data(count: NearbyOffer.maxFileBytes + 1), name: "x.hum") }
        #expect(!pair.sender.hasFile)
        #expect(pair.sender.localName == "Mac")
    }

    // MARK: Temporary files

    /// Hum sweeps old temporary files at launch, off the main actor, while a transfer may already be under
    /// way. The file being received is newer than the launch, so it stays and arrives whole.
    @Test func theLaunchSweepLeavesALiveTransferAlone() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NearbySweep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let leftover = try HumTemporaryFiles.makeFolder(prefix: HumTemporaryFiles.nearbyPrefix, in: dir)
        try FileManager.default.setAttributes([.creationDate: Date.now.addingTimeInterval(-3600)], ofItemAtPath: leftover.path)
        let launched = Date.now

        let received = NearbyTransferTests.Received()
        let pair = flow.makePair { received.files.append(($0, $1)) }
        pair.receiver.temporaryDirectory = dir
        let file = Data((0..<1_000_000).map { UInt8($0 % 251) })
        try flow.offer(pair, file: file)
        flow.accept(pair)
        pair.network.run(limit: 6)
        let live = try #require(pair.receiver.receivingFolder)

        let removed = await Task.detached { HumTemporaryFiles.sweep(createdBefore: launched, in: dir) }.value

        #expect(removed.map(\.lastPathComponent) == [leftover.lastPathComponent])
        #expect(FileManager.default.fileExists(atPath: live.path))
        pair.network.run()
        #expect(pair.receiver.state == .received)
        #expect(received.files.first?.data == file)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty, "nothing left once it's read")
    }
}

/// The pieces under the transfer, on their own.
@Suite("Nearby transfer: pieces")
struct NearbyPieceTests {
    @Test func sealedFramesCantBeReplayedReorderedOrCut() throws {
        let key = SymmetricKey(size: .bits256)
        var sealer = NearbySealer(key: key)
        let one = try sealer.seal(Data("one".utf8))
        let two = try sealer.seal(Data("two".utf8))

        var opener = NearbyOpener(key: key)
        #expect(try opener.open(one) == Data("one".utf8))
        #expect(throws: NearbyTransferError.badData) { try opener.open(one) }  // the same frame again
        #expect(try opener.open(two) == Data("two".utf8), "a refused frame doesn't move the count")

        var reordered = NearbyOpener(key: key)
        #expect(throws: NearbyTransferError.badData) { try reordered.open(two) }
        var cut = NearbyOpener(key: key)
        #expect(throws: NearbyTransferError.badData) { try cut.open(one.prefix(15)) }
        var otherKey = NearbyOpener(key: SymmetricKey(size: .bits256))
        #expect(throws: NearbyTransferError.badData) { try otherKey.open(one) }
    }

    @Test func helloesThatArentHumsAreRefused() throws {
        let sender = NearbyHandshake(isSender: true)
        #expect(throws: NearbyTransferError.badData) {
            try sender.finishAsSender(receiverHello: Data("HUM2".utf8) + Data(count: 32))
        }
        #expect(throws: NearbyTransferError.badData) { try sender.finishAsSender(receiverHello: NearbyHandshake.magic) }
        let receiver = NearbyHandshake(isSender: false)
        let (reveal, _) = try sender.finishAsSender(receiverHello: receiver.hello())
        #expect(throws: NearbyTransferError.badData) {
            try receiver.finishAsReceiver(senderHello: sender.hello(), reveal: reveal + Data([0]))
        }
    }

    @Test func everyEndingSaysWhatHappened() throws {
        let all: [NearbyTransferError] = [.badData, .tooBig, .unreadable, .lostConnection, .stopped, .otherCancelled,
                                          .otherTimedOut, .otherLeftFront, .leftFront, .youCancelled, .youDeclined,
                                          .couldNotConnect, .timedOut]
        #expect(all.allSatisfy { !$0.message.isEmpty })
        #expect(Set(all.map(\.message)).count == all.count, "each ending has its own words")
        // What this side's ending tells the other side, and how it reads there.
        let heard: [(NearbyTransferError, NearbyTransferError)] = [
            (.youCancelled, .otherCancelled), (.timedOut, .otherTimedOut), (.leftFront, .otherLeftFront),
            (.badData, .stopped), (.unreadable, .stopped), (.lostConnection, .stopped),
        ]
        for (here, there) in heard {
            #expect(NearbyTransferError(otherSide: here.reasonForOtherSide) == there, "\(here)")
        }
        // A reason from a newer Hum reads as a plain stop.
        #expect(try NearbyMessage.decode(Data([7, 200])) == .cancel(.error))
    }

    @Test func aFileArrivingIsCheckedAndCleanedUp() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("IncomingFile-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = Data("hello".utf8)

        let tooMuch = try IncomingFile(expected: 3, in: dir)
        #expect(throws: NearbyTransferError.unreadable) { try tooMuch.append(bytes) }
        tooMuch.discard()

        let short = try IncomingFile(expected: 10, in: dir)
        try short.append(bytes)
        #expect(short.fraction == 0.5)
        #expect(throws: NearbyTransferError.unreadable) { try short.finish(digest: Data(SHA256.hash(data: bytes))) }

        let changed = try IncomingFile(expected: 5, in: dir)
        try changed.append(bytes)
        #expect(throws: NearbyTransferError.unreadable) { try changed.finish(digest: Data(count: 32)) }

        let whole = try IncomingFile(expected: 5, in: dir)
        try whole.append(bytes)
        #expect(try whole.finish(digest: Data(SHA256.hash(data: bytes))) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty, "every ending removed its file")
    }
}
