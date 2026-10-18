// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(Compression)
import Compression
#endif

/// A minimal ZIP reader and writer with no dependencies.
///
/// - Writing uses STORE (no compression). Hum packages are mostly JPEG/HEIC/AAC media, which is
///   already compressed, so DEFLATE would save almost nothing.
/// - Reading supports STORE and DEFLATE, so `.obz` files from other AAC apps open too.
/// - ZIP64, encryption and multi-disk archives are not supported (and not needed for Hum files).
public enum ZipArchive {
    public struct Entry: Equatable, Sendable {
        public var path: String
        public var data: Data
        public init(path: String, data: Data) {
            self.path = path
            self.data = data
        }
    }

    static let localHeaderSignature: UInt32 = 0x0403_4B50
    static let centralHeaderSignature: UInt32 = 0x0201_4B50
    static let endSignature: UInt32 = 0x0605_4B50

    public static func looksLikeZip(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4).elementsEqual([0x50, 0x4B, 0x03, 0x04])
    }

    // MARK: Write

    public static func write(_ entries: [Entry]) -> Data {
        var out = Data()
        var central = Data()
        // A fixed timestamp (1980-01-01 00:00) keeps exports byte-identical for the same input.
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = (0 << 9) | (1 << 5) | 1

        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(out.count)

            out.appendLE(localHeaderSignature)
            out.appendLE(UInt16(20))       // version needed
            out.appendLE(UInt16(0x0800))   // flags: UTF-8 names
            out.appendLE(UInt16(0))        // method: store
            out.appendLE(dosTime)
            out.appendLE(dosDate)
            out.appendLE(crc)
            out.appendLE(size)
            out.appendLE(size)
            out.appendLE(UInt16(name.count))
            out.appendLE(UInt16(0))        // extra length
            out.append(name)
            out.append(entry.data)

            central.appendLE(centralHeaderSignature)
            central.appendLE(UInt16(0x031E)) // made by: Unix, 3.0
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(0x0800))
            central.appendLE(UInt16(0))
            central.appendLE(dosTime)
            central.appendLE(dosDate)
            central.appendLE(crc)
            central.appendLE(size)
            central.appendLE(size)
            central.appendLE(UInt16(name.count))
            central.appendLE(UInt16(0))    // extra
            central.appendLE(UInt16(0))    // comment
            central.appendLE(UInt16(0))    // disk
            central.appendLE(UInt16(0))    // internal attrs
            central.appendLE(UInt32(0o100644) << 16) // external attrs: regular file rw-r--r--
            central.appendLE(offset)
            central.append(name)
        }

        let centralOffset = UInt32(out.count)
        out.append(central)
        out.appendLE(endSignature)
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(entries.count))
        out.appendLE(UInt16(entries.count))
        out.appendLE(UInt32(central.count))
        out.appendLE(centralOffset)
        out.appendLE(UInt16(0))
        return out
    }

    // MARK: Read

    public enum ReadError: Error, Equatable {
        case notZip, truncated, unsupported(String), checksum(String)
        /// Over the limits below: too many files, too big once unpacked, or packed impossibly tight.
        case tooBig
    }

    /// Limits that keep a broken or hostile file from using up memory. A real Hum setup is far below
    /// them (a few thousand files, a few hundred MB of photos and recordings).
    public static let maxEntries = 20_000
    public static let maxTotalSize = 600 * 1024 * 1024
    /// DEFLATE can't pack data tighter than about 1032 to 1, so a file that claims more is lying.
    static let maxRatio = 1100

    /// Reads every file entry (directories are skipped). Throws on corrupt input; never traps.
    ///
    /// Every size is checked against the limits before anything is unpacked, and no two entries may
    /// share bytes (a "zip bomb" points thousands of entries at the same data).
    public static func read(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard let end = findEndRecord(bytes) else { throw ReadError.notZip }
        let count = Int(bytes.u16(at: end + 10))
        guard count <= maxEntries else { throw ReadError.tooBig }
        var cursor = Int(bytes.u32(at: end + 16))

        struct Pending {
            var name: String
            var method: UInt16
            var crc: UInt32
            var size: Int
            var header: Int
            var start: Int
            var end: Int
        }
        var pending: [Pending] = []
        var total = 0

        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, bytes.u32(at: cursor) == centralHeaderSignature else { throw ReadError.truncated }
            let flags = bytes.u16(at: cursor + 8)
            let method = bytes.u16(at: cursor + 10)
            let crc = bytes.u32(at: cursor + 16)
            let compressedSize = Int(bytes.u32(at: cursor + 20))
            let size = Int(bytes.u32(at: cursor + 24))
            let nameLength = Int(bytes.u16(at: cursor + 28))
            let extraLength = Int(bytes.u16(at: cursor + 30))
            let commentLength = Int(bytes.u16(at: cursor + 32))
            let localOffset = Int(bytes.u32(at: cursor + 42))
            guard cursor + 46 + nameLength <= bytes.count else { throw ReadError.truncated }
            let nameBytes = bytes[(cursor + 46)..<(cursor + 46 + nameLength)]
            let name = String(decoding: nameBytes, as: UTF8.self)
            cursor += 46 + nameLength + extraLength + commentLength

            if name.hasSuffix("/") { continue }  // directory
            if flags & 0x1 != 0 { throw ReadError.unsupported("encrypted file '\(name)'") }
            if compressedSize == 0xFFFF_FFFF || size == 0xFFFF_FFFF { throw ReadError.unsupported("ZIP64") }
            switch method {
            case 0: guard size == compressedSize else { throw ReadError.checksum(name) }
            case 8: guard size <= compressedSize * maxRatio + 1024 else { throw ReadError.tooBig }
            default: throw ReadError.unsupported("compression method \(method) in '\(name)'")
            }
            total += size
            guard total <= maxTotalSize else { throw ReadError.tooBig }

            guard localOffset + 30 <= bytes.count, bytes.u32(at: localOffset) == localHeaderSignature else { throw ReadError.truncated }
            let start = localOffset + 30 + Int(bytes.u16(at: localOffset + 26)) + Int(bytes.u16(at: localOffset + 28))
            guard start + compressedSize <= bytes.count else { throw ReadError.truncated }
            pending.append(Pending(name: name, method: method, crc: crc, size: size,
                                   header: localOffset, start: start, end: start + compressedSize))
        }

        // No two entries may overlap.
        let byPosition = pending.sorted { $0.header < $1.header }
        for (previous, next) in zip(byPosition, byPosition.dropFirst()) where next.header < previous.end {
            throw ReadError.unsupported("overlapping files")
        }

        var entries: [Entry] = []
        for item in pending {
            let raw = Data(bytes[item.start..<item.end])
            let content = item.method == 8 ? try inflate(raw, size: item.size) : raw
            guard content.count == item.size, CRC32.checksum(content) == item.crc else { throw ReadError.checksum(item.name) }
            entries.append(Entry(path: item.name, data: content))
        }
        return entries
    }

    static func inflate(_ raw: Data, size: Int) throws -> Data {
        #if canImport(Compression)
        if size > 0 {
            // COMPRESSION_ZLIB is raw DEFLATE (no zlib header), exactly what ZIP stores.
            var out = Data(count: size)
            let written = out.withUnsafeMutableBytes { dst in
                raw.withUnsafeBytes { src in
                    compression_decode_buffer(
                        dst.bindMemory(to: UInt8.self).baseAddress!, size,
                        src.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                        nil, COMPRESSION_ZLIB)
                }
            }
            if written == size { return out }
        }
        #endif
        do {
            return try Inflate.decompress(raw, expectedSize: size)
        } catch {
            throw ReadError.unsupported("damaged compressed data")
        }
    }

    private static func findEndRecord(_ b: [UInt8]) -> Int? {
        guard b.count >= 22 else { return nil }
        let lowest = max(0, b.count - 22 - 0xFFFF)
        var i = b.count - 22
        while i >= lowest {
            if b.u32(at: i) == endSignature { return i }
            i -= 1
        }
        return nil
    }
}

// MARK: - Little-endian helpers

extension Data {
    mutating func appendLE(_ v: UInt16) { append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)]) }
    mutating func appendLE(_ v: UInt32) {
        append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
}

extension [UInt8] {
    func u16(at i: Int) -> UInt16 {
        guard i + 2 <= count else { return 0 }
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }
    func u32(at i: Int) -> UInt32 {
        guard i + 4 <= count else { return 0 }
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}
