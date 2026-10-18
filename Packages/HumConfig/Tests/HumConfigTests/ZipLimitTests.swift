// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import HumConfig

/// A broken or hostile .hum file must fail quickly, never fill memory ("zip bombs").
@Suite("Zip limits")
struct ZipLimitTests {
    @Test func aHugeDeclaredSizeIsRefusedBeforeUnpacking() {
        let zip = craftZip([RawEntry(name: "media/a.jpg", method: 8, data: Data(count: 10), size: 4_000_000_000)])
        #expect(throws: ZipArchive.ReadError.tooBig) { try ZipArchive.read(zip) }
    }

    @Test func tooMuchOnceUnpackedIsRefused() {
        // 60 entries that each could honestly unpack to 11 MB: 660 MB in all, over the limit.
        let entries = (0..<60).map { RawEntry(name: "media/\($0).jpg", method: 8, data: Data(count: 10_000), size: 10_000 * 1100) }
        #expect(throws: ZipArchive.ReadError.tooBig) { try ZipArchive.read(craftZip(entries)) }
    }

    @Test func tooManyFilesIsRefused() {
        var zip = craftZip([RawEntry(name: "hum.json", method: 0, data: Data("{}".utf8))])
        // The end record's entry count (offset 10 from its start, the last 22 bytes).
        let at = zip.count - 22 + 10
        zip[at] = UInt8((ZipArchive.maxEntries + 1) & 0xFF)
        zip[at + 1] = UInt8((ZipArchive.maxEntries + 1) >> 8)
        #expect(throws: ZipArchive.ReadError.tooBig) { try ZipArchive.read(zip) }
    }

    @Test func entriesSharingTheSameBytesAreRefused() {
        let blob = Data(repeating: 7, count: 100)
        let zip = craftZip([RawEntry(name: "media/a.jpg", method: 0, data: blob),
                            RawEntry(name: "media/b.jpg", method: 0, data: blob)], sameOffset: true)
        #expect(throws: ZipArchive.ReadError.unsupported("overlapping files")) { try ZipArchive.read(zip) }
    }

    @Test func aStreamThatUnpacksToMoreThanItSaysStopsThere() throws {
        let bomb = zeroBomb(repeats: 1000)  // 258 001 zero bytes
        #expect(try Inflate.decompress(bomb).count == 1 + 258 * 1000)
        #expect(throws: (any Error).self) { try Inflate.decompress(bomb, expectedSize: 100) }
        // In a zip that claims 100 bytes it is refused, whichever inflater runs.
        let zip = craftZip([RawEntry(name: "media/a.jpg", method: 8, data: bomb, size: 100, crc: 0)])
        #expect(throws: (any Error).self) { try ZipArchive.read(zip) }
    }

    @Test func aTooBigPackageSaysSo() {
        let zip = craftZip([RawEntry(name: "media/a.jpg", method: 8, data: Data(count: 10), size: 4_000_000_000)])
        #expect(throws: HumConfigError.badPackage(.tooBig)) { try HumPackage.read(zip) }
    }

    @Test func normalPackagesStillOpen() throws {
        let entries = [ZipArchive.Entry(path: "hum.json", data: json("{}")),
                       ZipArchive.Entry(path: "media/a.jpg", data: Data((0..<50_000).map { UInt8($0 % 251) }))]
        #expect(try ZipArchive.read(ZipArchive.write(entries)) == entries)
        let deflated = craftZip([RawEntry(name: "a.bin", method: 8, data: zeroBomb(repeats: 10), size: 2581,
                                          crc: CRC32.checksum(Data(count: 2581)))])
        #expect(try ZipArchive.read(deflated) == [ZipArchive.Entry(path: "a.bin", data: Data(count: 2581))])
    }
}

// MARK: Making test zips by hand

struct RawEntry {
    var name: String
    var method: UInt16
    var data: Data
    var size: Int
    var crc: UInt32
    /// General purpose flags (bit 0: encrypted).
    var flags: UInt16

    init(name: String, method: UInt16, data: Data, size: Int? = nil, crc: UInt32? = nil, flags: UInt16 = 0) {
        self.name = name
        self.method = method
        self.data = data
        self.size = size ?? data.count
        self.crc = crc ?? CRC32.checksum(data)
        self.flags = flags
    }
}

/// A zip with exactly these headers, true or not. `sameOffset` points every entry at the first one's bytes.
func craftZip(_ entries: [RawEntry], sameOffset: Bool = false) -> Data {
    var out = Data()
    var central = Data()
    var firstOffset: UInt32?
    for entry in entries {
        let name = Data(entry.name.utf8)
        let offset = UInt32(out.count)
        if firstOffset == nil { firstOffset = offset }
        out.appendLE(ZipArchive.localHeaderSignature)
        out.appendLE(UInt16(20)); out.appendLE(entry.flags); out.appendLE(entry.method)
        out.appendLE(UInt16(0)); out.appendLE(UInt16(0))
        out.appendLE(entry.crc); out.appendLE(UInt32(entry.data.count)); out.appendLE(UInt32(truncatingIfNeeded: entry.size))
        out.appendLE(UInt16(name.count)); out.appendLE(UInt16(0))
        out.append(name)
        out.append(entry.data)

        central.appendLE(ZipArchive.centralHeaderSignature)
        central.appendLE(UInt16(20)); central.appendLE(UInt16(20)); central.appendLE(entry.flags); central.appendLE(entry.method)
        central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
        central.appendLE(entry.crc); central.appendLE(UInt32(entry.data.count)); central.appendLE(UInt32(truncatingIfNeeded: entry.size))
        central.appendLE(UInt16(name.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
        central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0))
        central.appendLE(sameOffset ? firstOffset! : offset)
        central.append(name)
    }
    let centralOffset = UInt32(out.count)
    out.append(central)
    out.appendLE(ZipArchive.endSignature)
    out.appendLE(UInt16(0)); out.appendLE(UInt16(0))
    out.appendLE(UInt16(entries.count)); out.appendLE(UInt16(entries.count))
    out.appendLE(UInt32(central.count)); out.appendLE(centralOffset)
    out.appendLE(UInt16(0))
    return out
}

/// A raw DEFLATE stream (fixed Huffman codes) that unpacks to 1 + 258 × `repeats` zero bytes: one
/// literal zero, then "copy 258 bytes from 1 back" again and again.
func zeroBomb(repeats: Int) -> Data {
    var bits = BitWriter()
    bits.write(1, count: 1)                 // last block
    bits.write(1, count: 2)                 // fixed Huffman codes
    bits.code(0x30, length: 8)              // literal 0
    for _ in 0..<repeats {
        bits.code(0xC5, length: 8)          // length 258 (symbol 285)
        bits.code(0, length: 5)             // distance 1
    }
    bits.code(0, length: 7)                 // end of block
    return bits.dataFlushed
}

struct BitWriter {
    private(set) var data = Data()
    private var buffer = 0
    private var count = 0

    /// Plain values go in least significant bit first.
    mutating func write(_ value: Int, count n: Int) {
        buffer |= value << count
        count += n
        while count >= 8 {
            data.append(UInt8(buffer & 0xFF))
            buffer >>= 8
            count -= 8
        }
    }

    /// Huffman codes go in most significant bit first.
    mutating func code(_ code: Int, length: Int) {
        var reversed = 0
        for i in 0..<length where code & (1 << i) != 0 { reversed |= 1 << (length - 1 - i) }
        write(reversed, count: length)
    }

    var dataFlushed: Data {
        var copy = self
        if copy.count > 0 { copy.data.append(UInt8(copy.buffer & 0xFF)) }
        return copy.data
    }
}
