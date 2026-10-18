// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Network
import Testing
import HumConfig
@testable import Hum

/// The wire format of a nearby transfer: frames, messages, offers and the key exchange.
@MainActor
@Suite("Nearby transfer: wire format")
struct NearbyWireTests {
    @Test func framesSurviveAnySplit() throws {
        let payloads = [Data("one".utf8), Data(repeating: 7, count: 70_000), Data([1])]
        let stream = payloads.map(NearbyFrames.frame).reduce(Data(), +)

        var whole = NearbyFrames()
        #expect(try whole.append(stream) == payloads)

        var byteByByte = NearbyFrames()
        var got: [Data] = []
        for byte in stream { got += try byteByByte.append(Data([byte])) }
        #expect(got == payloads)
    }

    @Test func framesRejectEmptyAndTooBig() throws {
        var empty = NearbyFrames()
        #expect(throws: NearbyTransferError.badData) { try empty.append(Data([0, 0, 0, 0])) }

        var tooBig = NearbyFrames()
        let length = UInt32(NearbyFrames.maxFrameBytes + 1)
        let header = Data([UInt8(length >> 24), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)])
        #expect(throws: NearbyTransferError.badData) { try tooBig.append(header) }

        var biggest = NearbyFrames()
        #expect(try biggest.append(NearbyFrames.frame(Data(count: NearbyFrames.maxFrameBytes))).count == 1)
    }

    @Test func messagesRoundTrip() throws {
        let offer = NearbyOffer(fileName: "Hum boards 2026-10-18.hum", byteCount: 1234, senderName: "Kitchen iPad")
        let messages: [NearbyMessage] = [.offer(offer), .accept, .decline, .chunk(Data([1, 2, 3])),
                                         .done(digest: Data(count: 32)), .gotIt, .cancel(.timedOut), .cancel(.leftFront)]
        for message in messages {
            #expect(try NearbyMessage.decode(message.encoded()) == message)
        }
    }

    @Test func messagesRejectWhatHumNeverSends() {
        #expect(throws: NearbyTransferError.badData) { try NearbyMessage.decode(Data()) }
        #expect(throws: NearbyTransferError.badData) { try NearbyMessage.decode(Data([99])) }
        #expect(throws: NearbyTransferError.badData) { try NearbyMessage.decode(Data([2, 0])) }
        #expect(throws: NearbyTransferError.badData) { try NearbyMessage.decode(Data([4])) }
        #expect(throws: NearbyTransferError.badData) { try NearbyMessage.decode(Data([4]) + Data(count: NearbyMessage.chunkBytes + 1)) }
        #expect(throws: NearbyTransferError.badData) { try NearbyMessage.decode(Data([5]) + Data(count: 31)) }
        #expect(throws: NearbyTransferError.badData) { try NearbyMessage.decode(Data([7])) }  // a stop without a reason
    }

    @Test func offerLimits() throws {
        func encode(_ offer: NearbyOffer) throws -> Data { try JSONEncoder().encode(offer) }
        let ok = NearbyOffer(fileName: "a.hum", byteCount: 10, senderName: "Mac")
        #expect(try NearbyOffer.decode(encode(ok)) == ok)

        var big = ok
        big.byteCount = NearbyOffer.maxFileBytes + 1
        #expect(throws: NearbyTransferError.tooBig) { try NearbyOffer.decode(encode(big)) }

        var empty = ok
        empty.byteCount = 0
        #expect(throws: NearbyTransferError.badData) { try NearbyOffer.decode(encode(empty)) }

        var future = ok
        future.version = 2
        #expect(throws: NearbyTransferError.badData) { try NearbyOffer.decode(encode(future)) }

        var long = ok
        long.senderName = String(repeating: "x", count: NearbyOffer.maxOfferBytes)
        #expect(throws: NearbyTransferError.badData) { try NearbyOffer.decode(encode(long)) }

        #expect(throws: NearbyTransferError.badData) { try NearbyOffer.decode(Data("not json".utf8)) }
    }

    @Test func receivedNamesAreMadeSafe() {
        #expect(NearbyOffer.safeFileName("../../etc/passwd") == "passwd.hum")
        #expect(NearbyOffer.safeFileName(".hidden.hum") == "hidden.hum")
        #expect(NearbyOffer.safeFileName("a/b:c.HUM") == "b-c.hum")
        #expect(NearbyOffer.safeFileName("") == "Hum boards.hum")
        #expect(NearbyOffer.safeFileName(String(repeating: "y", count: 300)).count == 84)
        #expect(NearbyOffer.safeDeviceName("  ") == "Another device")
        #expect(NearbyOffer.safeDeviceName("Line\nbreak") == "Line-break")
        // Invisible right-to-left overrides and zero-width spaces can't make look-alike names.
        #expect(NearbyOffer.safeDeviceName("i\u{200B}Pad\u{202E}") == "iPad")
    }

    @Test func handshakeGivesBothSidesTheSameCodeAndKeys() throws {
        let sender = NearbyHandshake(isSender: true)
        let receiver = NearbyHandshake(isSender: false)
        let senderHello = sender.hello()
        let (reveal, senderKeys) = try sender.finishAsSender(receiverHello: receiver.hello())
        var receiverKeys = try receiver.finishAsReceiver(senderHello: senderHello, reveal: reveal)
        var sealer = senderKeys.sealer
        #expect(senderKeys.code == receiverKeys.code)
        #expect(senderKeys.code.count == 6 && senderKeys.code.allSatisfy(\.isNumber))

        let first = try sealer.seal(Data("hello".utf8))
        let second = try sealer.seal(Data("again".utf8))
        #expect(try receiverKeys.opener.open(first) == Data("hello".utf8))
        // A frame can't be replayed or skipped.
        var replay = receiverKeys.opener
        #expect(throws: NearbyTransferError.badData) { try replay.open(first) }
        #expect(try receiverKeys.opener.open(second) == Data("again".utf8))

        // Changed on the way: rejected.
        var tampered = try sealer.seal(Data("third".utf8))
        tampered[0] ^= 1
        #expect(throws: NearbyTransferError.badData) { try receiverKeys.opener.open(tampered) }
    }

    @Test func handshakeRejectsAKeyThatDoesntMatchTheCommitment() throws {
        let sender = NearbyHandshake(isSender: true)
        let impostor = NearbyHandshake(isSender: true)
        let receiver = NearbyHandshake(isSender: false)
        let (reveal, _) = try impostor.finishAsSender(receiverHello: receiver.hello())
        #expect(throws: NearbyTransferError.badData) { try receiver.finishAsReceiver(senderHello: sender.hello(), reveal: reveal) }
        #expect(throws: NearbyTransferError.badData) { try sender.finishAsSender(receiverHello: Data("HUM2".utf8) + Data(count: 32)) }
    }

    @Test func twoTransfersGetDifferentCodes() throws {
        func code() throws -> String {
            let sender = NearbyHandshake(isSender: true)
            return try sender.finishAsSender(receiverHello: NearbyHandshake(isSender: false).hello()).keys.code
        }
        // Equal by chance once in a million; three in a row means the code isn't random.
        let codes = try [code(), code(), code()]
        #expect(Set(codes).count > 1)
    }
}

/// A sender and a receiver talking through an in-memory network.
@MainActor
@Suite("Nearby transfer: sending and receiving")
struct NearbyTransferTests {
    final class Received {
        var files: [(data: Data, name: String)] = []
    }

    struct Pair {
        let network: FakeNetwork
        let sender: NearbyTransfer
        let receiver: NearbyTransfer
        let senderTransport: FakeTransport
        let receiverTransport: FakeTransport
    }

    func makePair(deliver: @escaping (Data, String) -> Void) -> Pair {
        let network = FakeNetwork()
        let senderTransport = FakeTransport(name: "Mac", network: network)
        let receiverTransport = FakeTransport(name: "Kitchen iPad", network: network)
        let pair = Pair(network: network, sender: NearbyTransfer(role: .send, transport: senderTransport),
                        receiver: NearbyTransfer(role: .receive, transport: receiverTransport, deliver: deliver),
                        senderTransport: senderTransport, receiverTransport: receiverTransport)
        pair.receiver.start()
        pair.sender.start()
        network.run()
        return pair
    }

    /// Connects, then types the code the receiver shows, like a parent would. Returns that code.
    @discardableResult
    func offer(_ pair: Pair, file: Data) throws -> String? {
        try pair.sender.setFile(file, name: "Hum boards 2026-10-18.hum")
        guard let peer = pair.sender.peers.first else { return nil }
        pair.sender.send(to: peer)
        pair.network.run()
        guard case .pairing(let code) = pair.receiver.state else { return nil }
        pair.sender.confirm(code: code)
        pair.network.run()
        return code
    }

    /// The receiving parent types the code the sending device shows, like a parent would, to accept.
    func accept(_ pair: Pair) {
        guard case .waitingForAnswer(_, let code) = pair.sender.state else {
            Issue.record("sender should show its code, is \(pair.sender.state)")
            return
        }
        #expect(pair.receiver.accept(code: code))
    }

    @Test func aWholeSetupArrivesInTheImportPreviewUntouched() throws {
        let from = makeModel()
        let to = makeModel(starter: false)
        let file = try ImportService(model: from).exportData()
        let pair = makePair { data, name in to.requestImport(data: data, fileName: name) }

        #expect(pair.sender.peers.map(\.name) == ["Kitchen iPad"])
        try #require(try offer(pair, file: file) != nil)
        guard case .asking(let offer) = pair.receiver.state else {
            Issue.record("receiver should be asking, is \(pair.receiver.state)")
            return
        }
        #expect(offer.senderName == "Mac")
        #expect(offer.fileName == "Hum boards 2026-10-18.hum")
        #expect(offer.byteCount == file.count)
        #expect(to.pendingImport == nil, "nothing arrives before Accept")

        accept(pair)
        pair.network.run()
        #expect(pair.sender.state == .sent)
        #expect(pair.receiver.state == .received)
        #expect(!pair.receiverTransport.isAdvertising, "can't be found once the file is in")

        // The normal preview: nothing has changed until the parent chooses Merge or Replace.
        let pending = try #require(to.pendingImport)
        #expect(pending.fileName == "Hum boards 2026-10-18.hum")
        #expect(to.store.boards().isEmpty)
        #expect(Set(pending.loaded.document.boards.map(\.id)) == Set(from.store.boards().map(\.id)))
    }

    @Test func anInvalidFileIsRejectedByTheValidator() throws {
        let to = makeModel(starter: false)
        let pair = makePair { data, name in to.requestImport(data: data, fileName: name) }
        try offer(pair, file: Data("this is not a Hum file".utf8))
        accept(pair)
        pair.network.run()
        #expect(pair.receiver.state == .received)
        #expect(to.pendingImport == nil)
        #expect(to.importError != nil)
        #expect(to.store.boards().isEmpty)
    }

    @Test func aBigFileGoesInPieces() throws {
        let received = Received()
        let pair = makePair { received.files.append(($0, $1)) }
        let file = Data((0..<300_000).map { UInt8($0 % 251) })
        try offer(pair, file: file)
        accept(pair)
        pair.network.run()
        #expect(received.files.count == 1)
        #expect(received.files.first?.data == file)
        // 300 KB in 64 KB pieces.
        #expect(pair.senderTransport.channels.first?.sentFrames ?? 0 >= 5)
    }

    @Test func declining() throws {
        let received = Received()
        let pair = makePair { received.files.append(($0, $1)) }
        try offer(pair, file: Data(count: 100))
        pair.receiver.decline()
        pair.network.run()
        #expect(pair.sender.state == .declined)
        #expect(pair.receiver.state == .failed(.youDeclined))
        #expect(!pair.receiverTransport.isAdvertising, "can't be found until the parent starts again")
        #expect(received.files.isEmpty)

        // The parent can try again.
        pair.receiver.stop()
        pair.receiver.start()
        pair.network.run()
        try offer(pair, file: Data(count: 100))
        #expect({ if case .asking = pair.receiver.state { true } else { false } }())
    }

    @Test func senderCancelsWhileTheOtherDeviceIsAsking() throws {
        let pair = makePair { _, _ in }
        try offer(pair, file: Data(count: 100))
        pair.sender.cancel()
        pair.network.run()
        #expect(pair.sender.state == .looking)
        #expect(pair.receiver.state == .failed(.otherCancelled))
        #expect(!pair.receiverTransport.isAdvertising)
    }

    @Test func receiverCancelsHalfway() throws {
        let received = Received()
        let pair = makePair { received.files.append(($0, $1)) }
        try offer(pair, file: Data(count: 1_000_000))
        accept(pair)
        pair.network.run(limit: 12)
        #expect({ if case .transferring = pair.receiver.state { true } else { false } }())
        pair.receiver.cancel()
        pair.network.run()
        #expect(pair.sender.state == .failed(.otherCancelled))
        #expect(pair.receiver.state == .failed(.youCancelled))
        #expect(!pair.receiverTransport.isAdvertising)
        #expect(received.files.isEmpty)
    }

    @Test func closingTheScreenStopsDiscovery() throws {
        let pair = makePair { _, _ in }
        #expect(pair.receiverTransport.isAdvertising && pair.senderTransport.isBrowsing)
        pair.receiver.stop()
        pair.network.run()
        #expect(!pair.receiverTransport.isAdvertising)
        #expect(pair.sender.peers.isEmpty)
        pair.sender.stop()
        #expect(!pair.senderTransport.isBrowsing)
    }

    @Test func moreBytesThanOfferedAreRefused() throws {
        let received = Received()
        let pair = makePair { received.files.append(($0, $1)) }
        try offer(pair, file: Data(count: 100))
        // The sender's file changes after the offer: the receiver must not take more than it agreed to.
        try pair.sender.setFile(Data(count: 200_000), name: "x.hum")
        accept(pair)
        pair.network.run()
        #expect(pair.receiver.state == .failed(.unreadable))
        #expect(received.files.isEmpty)
    }

    @Test func bytesChangedOnTheWayAreRefused() throws {
        let received = Received()
        let pair = makePair { received.files.append(($0, $1)) }
        try offer(pair, file: Data(count: 100_000))
        // Flip a bit in every sealed piece of the file.
        for channel in pair.senderTransport.channels {
            channel.tamper = { data in
                guard data.count > 1000 else { return data }
                var data = data
                data[data.count - 1] ^= 1
                return data
            }
        }
        accept(pair)
        pair.network.run()
        #expect(pair.receiver.state == .failed(.badData))
        #expect(received.files.isEmpty)
        #expect({ if case .failed = pair.sender.state { true } else { false } }())
    }

    @Test func aSecondSenderIsTurnedAwayWhileTheFirstIsAsked() throws {
        let pair = makePair { _, _ in }
        try offer(pair, file: Data(count: 100))
        let other = NearbyTransfer(role: .send, transport: FakeTransport(name: "Phone", network: pair.network))
        other.start()
        pair.network.run()
        try other.setFile(Data(count: 100), name: "y.hum")
        other.send(to: try #require(other.peers.first))
        pair.network.run()
        #expect(other.state == .failed(.couldNotConnect))
        #expect({ if case .asking(let offer) = pair.receiver.state { offer.senderName == "Mac" } else { false } }())
    }

    @Test func aDeviceThatNeverOffersIsLetGo() async throws {
        let pair = makePair { _, _ in }
        pair.receiver.handshakeTimeout = .milliseconds(20)
        // Something connects and says nothing.
        let silent = pair.senderTransport.connect(to: try #require(pair.sender.peers.first))
        silent.start()
        pair.network.run()
        // Busy at first; once the silent one is let go, a real sender gets through.
        var asking = false
        for _ in 0..<100 where !asking {
            try await Task.sleep(for: .milliseconds(20))
            pair.network.run()
            try offer(pair, file: Data(count: 100))
            asking = { if case .asking = pair.receiver.state { true } else { false } }()
        }
        #expect(asking)
    }

    // MARK: The code check (security review, finding 1)

    @Test func nothingAboutTheFileLeavesTheSenderBeforeTheCodeIsTyped() throws {
        let pair = makePair { _, _ in }
        try pair.sender.setFile(Data(count: 1000), name: "Mia's school.hum")
        pair.sender.send(to: try #require(pair.sender.peers.first))
        pair.network.run()
        #expect({ if case .confirming = pair.sender.state { true } else { false } }())
        #expect({ if case .pairing = pair.receiver.state { true } else { false } }())
        // Only the two handshake frames: no offer (with its file name), no file.
        #expect(pair.senderTransport.channels.first?.sentFrames == 2)
    }

    @Test func aWrongCodeSendsNothingAndCanBeTypedAgain() throws {
        let pair = makePair { _, _ in }
        try pair.sender.setFile(Data(count: 1000), name: "x.hum")
        pair.sender.send(to: try #require(pair.sender.peers.first))
        pair.network.run()
        guard case .pairing(let code) = pair.receiver.state else {
            Issue.record("receiver should show a code, is \(pair.receiver.state)")
            return
        }
        let wrong = String(code.map { $0 == "9" ? "0" : Character(String(($0.wholeNumberValue ?? 0) + 1)) })
        #expect(!pair.sender.confirm(code: wrong))
        #expect(pair.sender.codeWasWrong)
        pair.network.run()
        #expect(pair.senderTransport.channels.first?.sentFrames == 2)
        #expect({ if case .pairing = pair.receiver.state { true } else { false } }())

        // Spaces as shown ("123 456") are fine.
        #expect(pair.sender.confirm(code: "\(code.prefix(3)) \(code.suffix(3))"))
        pair.network.run()
        #expect({ if case .asking = pair.receiver.state { true } else { false } }())
    }

    @Test func onlyDigitsCount() throws {
        let pair = makePair { _, _ in }
        try pair.sender.setFile(Data(count: 100), name: "x.hum")
        pair.sender.send(to: try #require(pair.sender.peers.first))
        pair.network.run()
        #expect(!pair.sender.confirm(code: "abcdef"))
        #expect({ if case .confirming = pair.sender.state { true } else { false } }())
    }

    // MARK: Timeouts and repeat tries (findings 5 and 6)

    @Test func anUnansweredPromptGoesAway() async throws {
        let pair = makePair { _, _ in }
        pair.receiver.personTimeout = .milliseconds(40)
        try offer(pair, file: Data(count: 100))
        #expect({ if case .asking = pair.receiver.state { true } else { false } }())
        try await eventually(pair) { pair.receiver.state == .failed(.timedOut) && pair.sender.state == .failed(.otherTimedOut) }
        #expect(pair.receiver.state == .failed(.timedOut))
        #expect(pair.sender.state == .failed(.otherTimedOut))
        #expect(!pair.receiverTransport.isAdvertising, "stops listening until the parent starts again")
    }

    @Test func aCodeNobodyTypesGoesAway() async throws {
        let pair = makePair { _, _ in }
        pair.receiver.personTimeout = .milliseconds(40)
        try pair.sender.setFile(Data(count: 100), name: "x.hum")
        pair.sender.send(to: try #require(pair.sender.peers.first))
        pair.network.run()
        try await eventually(pair) { pair.receiver.state == .failed(.timedOut) && pair.sender.state == .failed(.otherTimedOut) }
        #expect(pair.receiver.state == .failed(.timedOut))
        #expect(pair.sender.state == .failed(.otherTimedOut))
        #expect(!pair.receiverTransport.isAdvertising, "stops listening until the parent starts again")
    }

    @Test func aStalledTransferGivesUp() async throws {
        let pair = makePair { _, _ in }
        pair.sender.idleTimeout = .milliseconds(40)
        pair.receiver.idleTimeout = .milliseconds(40)
        try offer(pair, file: Data(count: 1_000_000))
        accept(pair)
        pair.network.run(limit: 5)
        // Nothing more arrives on either side.
        try await eventually(pair, runNetwork: false) {
            pair.receiver.state == .failed(.lostConnection) && pair.sender.state == .failed(.lostConnection)
        }
        #expect(pair.receiver.state == .failed(.lostConnection))
        #expect(pair.sender.state == .failed(.lostConnection))
    }

    /// Waits (up to 5 s, the main actor is busy when tests run in parallel) for the timers to act.
    func eventually(_ pair: Pair, runNetwork: Bool = true, _ condition: () -> Bool) async throws {
        for _ in 0..<250 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
            if runNetwork { pair.network.run() }
        }
    }

    @Test func afterADeclineNobodyElseGetsIn() throws {
        // A stranger can't keep putting prompts on the screen: after any ending but a finished transfer,
        // the receiver stops listening until the parent taps to receive again.
        let pair = makePair { _, _ in }
        try offer(pair, file: Data(count: 100))
        pair.receiver.decline()
        pair.network.run()
        #expect(pair.sender.peers.isEmpty, "it has gone from every list")
        #expect(try offer(pair, file: Data(count: 100)) == nil)
        #expect(pair.receiver.state == .failed(.youDeclined))
    }

    // MARK: Every ending says why, and leads somewhere

    /// A six-digit code that is certainly not `code`.
    func differentCode(_ code: String) -> String {
        String(code.map { Character(String((($0.wholeNumberValue ?? 0) + 1) % 10)) })
    }

    /// Connects and gets the receiver to show its code (the sender is typing it).
    func pairUp(_ pair: Pair) throws {
        try pair.sender.setFile(Data(count: 100), name: "x.hum")
        pair.sender.send(to: try #require(pair.sender.peers.first))
        pair.network.run()
    }

    @Test func cancelWhileTheCodeShowsOnTheReceiver() throws {
        let pair = makePair { _, _ in }
        try pairUp(pair)
        pair.receiver.cancel()
        pair.network.run()
        #expect(pair.receiver.state == .failed(.youCancelled))
        #expect(pair.sender.state == .failed(.otherCancelled))
    }

    @Test func cancelWhileTypingOnTheSender() throws {
        let pair = makePair { _, _ in }
        try pairUp(pair)
        pair.sender.cancel()
        pair.network.run()
        #expect(pair.sender.state == .looking)
        #expect(pair.receiver.state == .failed(.otherCancelled))
    }

    @Test func theSenderGoingToTheBackground() throws {
        let pair = makePair { _, _ in }
        try pairUp(pair)
        pair.sender.leave()
        pair.network.run()
        #expect(pair.sender.state == .failed(.leftFront))
        #expect(pair.receiver.state == .failed(.otherLeftFront))
    }

    @Test func theReceiverGoingToTheBackground() throws {
        let pair = makePair { _, _ in }
        try offer(pair, file: Data(count: 100))
        pair.receiver.leave()
        pair.network.run()
        #expect(pair.receiver.state == .failed(.leftFront))
        #expect(pair.sender.state == .failed(.otherLeftFront))
        #expect(!pair.receiverTransport.isAdvertising)
    }

    @Test func theNetworkGoingAway() throws {
        let pair = makePair { _, _ in }
        try offer(pair, file: Data(count: 100))
        // The receiver's end of the connection disappears without a word.
        pair.senderTransport.channels.last?.other?.close()
        pair.network.run()
        #expect(pair.sender.state == .failed(.lostConnection))
    }

    @Test func aWrongCodeIsNotAnEnding() throws {
        // Typing the wrong code on either side keeps the try going, with the field cleared.
        let pair = makePair { _, _ in }
        try pairUp(pair)
        guard case .pairing(let code) = pair.receiver.state else {
            Issue.record("receiver should show a code, is \(pair.receiver.state)")
            return
        }
        #expect(!pair.sender.confirm(code: differentCode(code)))
        #expect({ if case .confirming = pair.sender.state { true } else { false } }())
        #expect(pair.sender.confirm(code: code))
        pair.network.run()
        guard case .waitingForAnswer(_, let senderCode) = pair.sender.state else { return }
        #expect(!pair.receiver.accept(code: differentCode(senderCode)))
        pair.network.run()
        #expect({ if case .asking = pair.receiver.state { true } else { false } }())
        #expect({ if case .waitingForAnswer = pair.sender.state { true } else { false } }())
    }

    @Test func tryAgainAfterAnEndingFindsTheDeviceAgain() throws {
        let pair = makePair { _, _ in }
        try offer(pair, file: Data(count: 100))
        pair.receiver.decline()
        pair.network.run()
        #expect(pair.sender.peers.isEmpty)

        // "Receive again" on the other device: it shows up in the list again by itself.
        pair.receiver.restart()
        pair.network.run()
        #expect(pair.sender.peers.map(\.name) == ["Kitchen iPad"])

        // "Try again" here clears what happened and looks afresh.
        pair.sender.restart()
        pair.network.run()
        #expect(pair.sender.state == .looking)
        #expect(pair.sender.peers.map(\.name) == ["Kitchen iPad"])
        #expect(try offer(pair, file: Data(count: 100)) != nil)
        #expect({ if case .asking = pair.receiver.state { true } else { false } }())
    }

    @Test func everyTryStartsClean() throws {
        let pair = makePair { _, _ in }
        try pairUp(pair)
        guard case .pairing(let code) = pair.receiver.state else { return }
        #expect(!pair.sender.confirm(code: differentCode(code)))
        let first = pair.sender.attempt
        #expect(pair.sender.codeWasWrong)

        pair.sender.cancel()
        pair.network.run()
        pair.receiver.restart()
        pair.network.run()
        try pairUp(pair)
        #expect(pair.sender.attempt == first + 1, "a new attempt: code fields are rebuilt empty")
        #expect(!pair.sender.codeWasWrong, "no old error")
        #expect({ if case .confirming = pair.sender.state { true } else { false } }())

        // Leaving the screen and coming back starts from nothing too.
        pair.sender.stop()
        #expect(pair.sender.state == .idle && pair.sender.peers.isEmpty && !pair.sender.codeWasWrong)
    }

    // MARK: Nothing is left on disk

    /// Starts receiving a big file and returns the folder it's being written to.
    func receiveHalfway(_ pair: Pair) throws -> URL {
        try offer(pair, file: Data(count: 1_000_000))
        accept(pair)
        pair.network.run(limit: 6)
        let folder = try #require(pair.receiver.receivingFolder)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        return folder
    }

    @Test func aFinishedTransferLeavesNoFile() throws {
        let pair = makePair { _, _ in }
        let folder = try receiveHalfway(pair)
        pair.network.run()
        #expect(pair.receiver.state == .received)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func everyOtherEndingLeavesNoFile() async throws {
        // Cancel here, cancel there, a broken file, a lost connection, a stall, and closing the screen.
        let endings: [(String, (Pair) async throws -> Void)] = [
            ("receiver cancels", { pair in pair.receiver.cancel(); pair.network.run() }),
            ("sender cancels", { pair in pair.sender.cancel(); pair.network.run() }),
            ("connection lost", { pair in pair.senderTransport.channels.last?.close(); pair.network.run() }),
            ("screen closed", { pair in pair.receiver.stop(); pair.network.run() }),
            ("stalled", { pair in
                pair.receiver.idleTimeout = .milliseconds(30)
                try await self.eventually(pair, runNetwork: false) { if case .failed = pair.receiver.state { true } else { false } }
            }),
        ]
        for (name, end) in endings {
            let pair = makePair { _, _ in }
            let folder = try receiveHalfway(pair)
            try await end(pair)
            #expect(pair.receiver.receivingFolder == nil, "\(name)")
            #expect(!FileManager.default.fileExists(atPath: folder.path), "\(name): file left behind")
        }
    }

    @Test func aChangedFileLeavesNoFile() throws {
        let pair = makePair { _, _ in }
        try offer(pair, file: Data(count: 100))
        try pair.sender.setFile(Data(count: 200_000), name: "x.hum")  // more than offered
        accept(pair)
        let folder = try #require(pair.receiver.receivingFolder)
        pair.network.run()
        #expect(pair.receiver.state == .failed(.unreadable))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    // MARK: The sender's code (second review, finding A)

    @Test func aStrangersOfferNeedsTheSendersCode() throws {
        let received = Received()
        let pair = makePair { received.files.append(($0, $1)) }
        try offer(pair, file: Data(count: 100))
        guard case .waitingForAnswer(_, let code) = pair.sender.state else {
            Issue.record("sender should show its code, is \(pair.sender.state)")
            return
        }
        // Someone who can't see the sending screen can't accept for it.
        let wrong = String(code.map { $0 == "9" ? "0" : Character(String(($0.wholeNumberValue ?? 0) + 1)) })
        #expect(!pair.receiver.accept(code: wrong))
        #expect(pair.receiver.codeWasWrong)
        pair.network.run()
        #expect({ if case .asking = pair.receiver.state { true } else { false } }())
        #expect({ if case .waitingForAnswer = pair.sender.state { true } else { false } }())
        #expect(pair.receiver.accept(code: code))
        pair.network.run()
        #expect(received.files.count == 1)
    }

    @Test func theTwoCodesDiffer() throws {
        let pair = makePair { _, _ in }
        let receiverCode = try #require(try offer(pair, file: Data(count: 100)))
        guard case .waitingForAnswer(_, let senderCode) = pair.sender.state else {
            Issue.record("sender should show its code")
            return
        }
        // Equal by chance once in a million.
        #expect(senderCode != receiverCode)
        #expect(!pair.receiver.accept(code: receiverCode))
    }

    @Test func digitsFromAnyKeyboardCount() {
        #expect(nearbyCodeDigits("١٢٣ ٤٥٦") == "123456")   // Arabic-Indic
        #expect(nearbyCodeDigits("１２３４５６") == "123456")  // full-width
        #expect(nearbyCodeDigits("12a-34 56") == "123456")
    }

    // MARK: Trickled bytes (second review, finding D)

    @Test func bytesThatNeverMakeAFrameDontKeepTheReceiverBusy() async throws {
        let pair = makePair { _, _ in }
        pair.receiver.handshakeTimeout = .milliseconds(40)
        // Something connects and drips a byte at a time of a frame it never finishes.
        let dripper = pair.senderTransport.connect(to: try #require(pair.sender.peers.first))
        dripper.start()
        pair.network.run()
        dripper.send(Data([0, 1])) { _ in }   // a frame header that promises 64 KB…
        var asking = false
        for _ in 0..<100 where !asking {
            dripper.send(Data([7])) { _ in }  // …and never delivers it
            try await Task.sleep(for: .milliseconds(20))
            pair.network.run()
            try offer(pair, file: Data(count: 100))
            asking = { if case .asking = pair.receiver.state { true } else { false } }()
        }
        #expect(asking, "the dripping device was let go and a real sender got through")
    }

    @Test func tunnelsAreRecognized() {
        #expect(NetworkTransport.isTunnel(interfaceName: "utun3"))
        #expect(NetworkTransport.isTunnel(interfaceName: "ipsec0"))
        #expect(!NetworkTransport.isTunnel(interfaceName: "en0"))
        #expect(!NetworkTransport.isTunnel(interfaceName: "awdl0"))
        #expect(!NetworkTransport.isTunnel(interfaceName: "lo0"))
    }

    // MARK: Local addresses only (finding 4)

    @Test func onlyLocalAddressesMayConnect() {
        func local(_ host: NWEndpoint.Host) -> Bool { NetworkTransport.isLocal(.hostPort(host: host, port: 4000)) }
        #expect(local("192.168.1.20"))
        #expect(local("10.0.0.5"))
        #expect(local("172.20.1.1"))
        #expect(local("169.254.3.4"))
        #expect(local("127.0.0.1"))
        #expect(local("fe80::1c2b:3cff:fe4d:5e6f"))
        #expect(local("fd12:3456:789a::1"))
        #expect(local("::1"))
        #expect(local("::ffff:192.168.1.20"))
        #expect(!local("8.8.8.8"))
        #expect(!local("172.32.0.1"))
        #expect(!local("100.64.0.1"))
        #expect(!local("2001:4860:4860::8888"))
        #expect(!local("::ffff:8.8.8.8"))
        #expect(!NetworkTransport.isLocal(.service(name: "x", type: "_hum-setup._tcp", domain: "local.", interface: nil)))
    }
}

// MARK: Fakes

/// Delivers everything later, in order, when a test calls `run`, like a real network but repeatable.
@MainActor
final class FakeNetwork {
    private var queue: [() -> Void] = []
    var transports: [FakeTransport] = []

    func later(_ work: @escaping () -> Void) { queue.append(work) }

    func run(limit: Int = 100_000) {
        var steps = 0
        while !queue.isEmpty && steps < limit {
            queue.removeFirst()()
            steps += 1
        }
    }

    /// Tells every browsing device who is advertising now.
    func announce() {
        let peers = transports.filter(\.isAdvertising).map { NearbyPeer(id: $0.localName, name: $0.localName) }
        for transport in transports where transport.isBrowsing {
            later { transport.onEvent?(.peers(peers)) }
        }
    }
}

@MainActor
final class FakeTransport: NearbyTransport {
    var onEvent: ((NearbyTransportEvent) -> Void)?
    let localName: String
    let network: FakeNetwork
    private(set) var isAdvertising = false
    private(set) var isBrowsing = false
    /// Channels this device opened.
    private(set) var channels: [FakeChannel] = []

    init(name: String, network: FakeNetwork) {
        localName = name
        self.network = network
        network.transports.append(self)
    }

    func advertise() {
        isAdvertising = true
        network.announce()
    }

    func browse() {
        isBrowsing = true
        network.announce()
    }

    func connect(to peer: NearbyPeer) -> NearbyChannel {
        let mine = FakeChannel(network: network)
        let theirs = FakeChannel(network: network)
        mine.other = theirs
        theirs.other = mine
        channels.append(mine)
        if let receiver = network.transports.first(where: { $0.isAdvertising && $0.localName == peer.id }) {
            network.later { receiver.onEvent?(.incoming(theirs)) }
        } else {
            mine.other = nil
        }
        return mine
    }

    func stop() {
        isAdvertising = false
        isBrowsing = false
        network.announce()
    }
}

@MainActor
final class FakeChannel: NearbyChannel {
    var onEvent: ((NearbyChannelEvent) -> Void)?
    var other: FakeChannel?
    /// Changes bytes on the way out, to test what the other side does with them.
    var tamper: ((Data) -> Data)?
    private(set) var sentFrames = 0
    private let network: FakeNetwork
    private var started = false
    private(set) var closed = false
    private var waiting: [Data] = []

    init(network: FakeNetwork) { self.network = network }

    func start() {
        started = true
        network.later { [self] in
            guard !closed else { return }
            if other == nil { return remoteClosed() }
            onEvent?(.ready)
            for data in waiting { onEvent?(.received(data)) }
            waiting = []
        }
    }

    func send(_ data: Data, completion: @escaping (Bool) -> Void) {
        guard !closed, let other else {
            network.later { completion(false) }
            return
        }
        sentFrames += 1
        let bytes = tamper?(data) ?? data
        network.later {
            other.arrive(bytes)
            completion(true)
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        onEvent = nil
        if let other { network.later { other.remoteClosed() } }
    }

    private func arrive(_ data: Data) {
        guard !closed else { return }
        if started { onEvent?(.received(data)) } else { waiting.append(data) }
    }

    private func remoteClosed() {
        guard !closed else { return }
        closed = true
        let onEvent = self.onEvent
        self.onEvent = nil
        onEvent?(.closed)
    }
}

/// The real Network framework transport, sender and receiver in one app, over Bonjour and TCP.
/// Off by default (it needs the local network): run with HUM_LIVE_NEARBY=1
/// (`TEST_RUNNER_HUM_LIVE_NEARBY=1` through xcodebuild).
@MainActor
@Suite("Nearby transfer: real network", .enabled(if: ProcessInfo.processInfo.environment["HUM_LIVE_NEARBY"] == "1"))
struct NearbyLiveTests {
    @Test(.timeLimit(.minutes(1))) func sendsOverTheLocalNetwork() async throws {
        let received = NearbyTransferTests.Received()
        let receiver = NearbyTransfer(role: .receive, transport: NetworkTransport()) { received.files.append(($0, $1)) }
        let sender = NearbyTransfer(role: .send, transport: NetworkTransport())
        defer {
            receiver.stop()
            sender.stop()
        }
        let file = Data((0..<1_500_000).map { UInt8($0 % 253) })
        try sender.setFile(file, name: "Live.hum")
        receiver.start()
        sender.start()

        try await waitUntil { sender.peers.contains { $0.name == receiver.localName } }
        sender.send(to: try #require(sender.peers.first { $0.name == receiver.localName }))
        try await waitUntil { if case .pairing = receiver.state { true } else { false } }
        guard case .pairing(let code) = receiver.state else {
            Issue.record("receiver \(receiver.state), sender \(sender.state)")
            return
        }
        #expect(sender.confirm(code: code))
        try await waitUntil { if case .asking = receiver.state { true } else { false } }
        guard case .waitingForAnswer(_, let senderCode) = sender.state else {
            Issue.record("sender \(sender.state)")
            return
        }
        #expect(receiver.accept(code: senderCode))
        try await waitUntil { sender.state == .sent && received.files.count == 1 }
        #expect(received.files.first?.data == file)
        #expect(received.files.first?.name == "Live.hum")
        #expect(receiver.state == .received)
    }

    /// Sends a small setup to Hum on another device or simulator whose Receive screen is open, named by
    /// HUM_LIVE_NEARBY_PEER. A person writes the code that device shows into the file named by
    /// HUM_LIVE_NEARBY_CODE_FILE, then types the code this test prints on that device and taps Accept,
    /// within 90 seconds each.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HUM_LIVE_NEARBY_PEER"] != nil), .timeLimit(.minutes(4)))
    func sendsToAnotherDevice() async throws {
        let environment = ProcessInfo.processInfo.environment
        let name = try #require(environment["HUM_LIVE_NEARBY_PEER"])
        let codeFile = URL(fileURLWithPath: try #require(environment["HUM_LIVE_NEARBY_CODE_FILE"]))
        let sender = NearbyTransfer(role: .send, transport: NetworkTransport())
        defer { sender.stop() }
        try sender.setFile(try ImportService(model: makeModel()).exportData(), name: "Live starter.hum")
        sender.start()
        try await waitUntil { sender.peers.contains { $0.name == name } }
        sender.send(to: try #require(sender.peers.first { $0.name == name }))
        try await waitUntil { if case .confirming = sender.state { true } else { false } }
        print("Nearby live: type the code into \(codeFile.path)")
        var typed = ""
        try await waitUntil(seconds: 90) {
            typed = (try? String(contentsOf: codeFile, encoding: .utf8)) ?? ""
            return nearbyCodeDigits(typed).count == 6
        }
        #expect(sender.confirm(code: typed))
        print("Nearby live: on the other device, type \(sender.state)")
        try await waitUntil(seconds: 90) { sender.state == .sent }
    }

    private func waitUntil(seconds: Int = 20, _ condition: () -> Bool) async throws {
        for _ in 0..<(seconds * 20) where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition())
    }
}
