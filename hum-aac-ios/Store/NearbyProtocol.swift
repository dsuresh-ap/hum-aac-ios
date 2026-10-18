// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit

// What two devices say to each other when one sends a Hum file to the other (see `NearbyTransfer`).
//
// 1. Handshake, in plain frames. The sender sends "HUM1" + a hash of its key, the receiver answers
//    "HUM1" + its key, then the sender shows its key. Both work out the same secret keys and the same
//    six-digit code. The sender commits to its key before it sees the receiver's, so a device in the
//    middle can't choose keys that give both sides the same code.
// 2. The receiver shows the code and the parent types it on the sender. Only then is anything about the
//    file sent. Then the sender shows a second code and the parent types that on the receiver before
//    Accept, so each side knows the other is the parent's own device. Every frame after the handshake is
//    sealed (ChaChaPoly, a key and a counter for each direction): the offer, Accept or Decline, the file
//    in pieces, a check of the whole file, and "got it".

/// Frames on a byte stream: 4 bytes of length (big-endian), then that many bytes.
nonisolated struct NearbyFrames {
    /// A 64 KB piece of the file, its type byte and seal fit with room to spare.
    static let maxFrameBytes = 128 * 1024

    private var buffer = Data()

    static func frame(_ payload: Data) -> Data {
        let length = UInt32(payload.count)
        return Data([UInt8(length >> 24), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)]) + payload
    }

    /// Adds bytes as they arrive and returns every frame that's now complete. An empty or too-big
    /// frame means the other side isn't Hum (or is broken), so it throws.
    mutating func append(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard length > 0, length <= Self.maxFrameBytes else { throw NearbyTransferError.badData }
            guard buffer.count >= 4 + length else { break }
            frames.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer = Data(buffer.dropFirst(4 + length))
        }
        return frames
    }
}

/// One sealed message.
nonisolated enum NearbyMessage: Equatable, Sendable {
    /// Sender → receiver: what's coming. Shown in the Accept prompt.
    case offer(NearbyOffer)
    case accept
    case decline
    /// Sender → receiver: the next piece of the file.
    case chunk(Data)
    /// Sender → receiver: the whole file has been sent; its SHA-256.
    case done(digest: Data)
    /// Receiver → sender: the file arrived whole.
    case gotIt
    /// Either side stopped, and why, so the other screen can say what happened.
    case cancel(NearbyStopReason)

    /// The biggest piece of the file in one message.
    static let chunkBytes = 64 * 1024

    func encoded() -> Data {
        switch self {
        case .offer(let offer): Data([1]) + ((try? JSONEncoder().encode(offer)) ?? Data())
        case .accept: Data([2])
        case .decline: Data([3])
        case .chunk(let bytes): Data([4]) + bytes
        case .done(let digest): Data([5]) + digest
        case .gotIt: Data([6])
        case .cancel(let reason): Data([7, reason.rawValue])
        }
    }

    static func decode(_ data: Data) throws -> NearbyMessage {
        guard let type = data.first else { throw NearbyTransferError.badData }
        let body = Data(data.dropFirst())
        switch type {
        case 1: return .offer(try NearbyOffer.decode(body))
        case 2 where body.isEmpty: return .accept
        case 3 where body.isEmpty: return .decline
        case 4 where !body.isEmpty && body.count <= chunkBytes: return .chunk(body)
        case 5 where body.count == SHA256.byteCount: return .done(digest: body)
        case 6 where body.isEmpty: return .gotIt
        case 7 where body.count == 1: return .cancel(NearbyStopReason(rawValue: body[0]) ?? .error)
        default: throw NearbyTransferError.badData
        }
    }
}

/// Why one side stopped, sent with `cancel`.
nonisolated enum NearbyStopReason: UInt8, Sendable {
    /// Something went wrong (bad data, a lost file, an unknown reason).
    case error = 0
    /// The parent tapped Cancel.
    case cancelled = 1
    /// Nobody typed the code or answered in time.
    case timedOut = 2
    /// Hum stopped being the app in front.
    case leftFront = 3
}

/// What the sender says before anything is sent.
nonisolated struct NearbyOffer: Codable, Equatable, Sendable {
    static let currentVersion = 1
    /// Large enough for a big setup full of photos and recordings, small enough for an older iPad's
    /// memory while the file is imported. Bigger setups can still go by AirDrop or Files.
    static let maxFileBytes = 200 * 1024 * 1024
    /// The offer itself stays tiny.
    static let maxOfferBytes = 1024

    var version = NearbyOffer.currentVersion
    var fileName: String
    var byteCount: Int
    /// The sending device's name, as it calls itself.
    var senderName: String

    static func decode(_ data: Data) throws -> NearbyOffer {
        guard data.count <= maxOfferBytes,
              let offer = try? JSONDecoder().decode(NearbyOffer.self, from: data),
              offer.version == currentVersion, offer.byteCount > 0 else {
            throw NearbyTransferError.badData
        }
        guard offer.byteCount <= maxFileBytes else { throw NearbyTransferError.tooBig }
        return NearbyOffer(fileName: safeFileName(offer.fileName), byteCount: offer.byteCount,
                           senderName: safeDeviceName(offer.senderName))
    }

    /// A plain file name ending in ".hum": no folders, no hidden files, not too long.
    static func safeFileName(_ name: String) -> String {
        var base = (name as NSString).lastPathComponent
        if base.lowercased().hasSuffix(".hum") { base = String(base.dropLast(4)) }
        base = cleaned(base, limit: 80)
        if base.isEmpty { base = String(localized: "Hum boards") }
        return base + ".hum"
    }

    static func safeDeviceName(_ name: String) -> String {
        let name = cleaned(name, limit: 63)
        return name.isEmpty ? String(localized: "Another device") : name
    }

    private static func cleaned(_ text: String, limit: Int) -> String {
        // Invisible formatting (right-to-left overrides, zero-width spaces) could make one name look like
        // another, so it goes.
        let visible = String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.properties.generalCategory != .format }))
        let text = String(visible.map { "/\\:".contains($0) || $0.isNewline || $0.unicodeScalars.contains { $0.properties.generalCategory == .control } ? "-" : $0 })
        return String(text.trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines)).prefix(limit))
    }
}

/// The key exchange that starts every transfer.
nonisolated struct NearbyHandshake {
    static let magic = Data("HUM1".utf8)
    static let helloBytes = magic.count + 32

    let isSender: Bool
    private let key = Curve25519.KeyAgreement.PrivateKey()

    init(isSender: Bool) { self.isSender = isSender }

    private var publicKey: Data { key.publicKey.rawRepresentation }

    /// The first frame each side sends: "HUM1" + (sender) a hash of its key, or (receiver) its key.
    func hello() -> Data {
        Self.magic + (isSender ? Data(SHA256.hash(data: publicKey)) : publicKey)
    }

    /// Sender, once the receiver's hello arrives: the frame that shows our key, and the keys for both ways.
    func finishAsSender(receiverHello: Data) throws -> (reveal: Data, keys: NearbyKeys) {
        let receiverKey = try Self.body(of: receiverHello)
        return (publicKey, try keys(senderKey: publicKey, receiverKey: receiverKey))
    }

    /// Receiver, once the sender has shown its key: checks it matches the hash sent first.
    func finishAsReceiver(senderHello: Data, reveal: Data) throws -> NearbyKeys {
        let commitment = try Self.body(of: senderHello)
        guard reveal.count == 32, Data(SHA256.hash(data: reveal)) == commitment else { throw NearbyTransferError.badData }
        return try keys(senderKey: reveal, receiverKey: publicKey)
    }

    private static func body(of hello: Data) throws -> Data {
        guard hello.count == helloBytes, hello.prefix(magic.count) == magic else { throw NearbyTransferError.badData }
        return Data(hello.dropFirst(magic.count))
    }

    private func keys(senderKey: Data, receiverKey: Data) throws -> NearbyKeys {
        let other = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: isSender ? receiverKey : senderKey)
        let secret = try key.sharedSecretFromKeyAgreement(with: other)
        let salt = senderKey + receiverKey
        func derive(_ info: String) -> SymmetricKey {
            secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data(info.utf8), outputByteCount: 32)
        }
        let toReceiver = derive("hum nearby v1 sender to receiver")
        let toSender = derive("hum nearby v1 receiver to sender")
        func code(_ info: String) -> String {
            let number = derive(info).withUnsafeBytes { $0.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
            return String(format: "%06u", number % 1_000_000)
        }
        return NearbyKeys(sealer: NearbySealer(key: isSender ? toReceiver : toSender),
                          opener: NearbyOpener(key: isSender ? toSender : toReceiver),
                          code: code("hum nearby v1 code"), senderCode: code("hum nearby v1 sender code"))
    }
}

nonisolated struct NearbyKeys {
    var sealer: NearbySealer
    var opener: NearbyOpener
    /// Six digits, the same on both devices only if nobody is in the middle. The receiver shows it and the
    /// parent types it on the sender.
    let code: String
    /// A second code: the sender shows it and the parent types it on the receiver.
    let senderCode: String
}

/// Seals outgoing frames. The nonce is a counter, so frames can't be replayed, dropped or reordered.
nonisolated struct NearbySealer {
    let key: SymmetricKey
    private(set) var counter: UInt64 = 0

    init(key: SymmetricKey) { self.key = key }

    /// Ciphertext + tag (the nonce isn't sent: both sides count).
    mutating func seal(_ plain: Data) throws -> Data {
        let box = try ChaChaPoly.seal(plain, using: key, nonce: try nearbyNonce(counter))
        counter += 1
        return Data(box.ciphertext) + box.tag
    }
}

nonisolated struct NearbyOpener {
    let key: SymmetricKey
    private(set) var counter: UInt64 = 0

    init(key: SymmetricKey) { self.key = key }

    mutating func open(_ sealed: Data) throws -> Data {
        guard sealed.count >= 16 else { throw NearbyTransferError.badData }
        do {
            let box = try ChaChaPoly.SealedBox(nonce: try nearbyNonce(counter), ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
            let plain = try ChaChaPoly.open(box, using: key)
            counter += 1
            return plain
        } catch {
            throw NearbyTransferError.badData
        }
    }
}

private nonisolated func nearbyNonce(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
    try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + withUnsafeBytes(of: counter.bigEndian) { Data($0) })
}

/// What a parent typed as a six-digit code: just the digits, in any script ("١٢٣ ٤٥٦" is "123456").
nonisolated func nearbyCodeDigits(_ typed: String) -> String {
    String(typed.compactMap { $0.isNumber ? $0.wholeNumberValue.map { Character(String($0)) } : nil })
}
