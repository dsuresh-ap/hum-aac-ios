// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import HumConfig

/// Every way a zip can be broken gets a clear error, and the limits let through what they promise.
@Suite("Zip reading")
struct ZipReadTests {
    let config = RawEntry(name: "hum.json", method: 0, data: json("{}"))

    @Test func notAZipSaysSo() {
        #expect(throws: ZipArchive.ReadError.notZip) { try ZipArchive.read(Data()) }
        #expect(throws: ZipArchive.ReadError.notZip) { try ZipArchive.read(json("Some text that is long enough to look through.")) }
        #expect(!ZipArchive.looksLikeZip(json("PK")))
        #expect(ZipArchive.looksLikeZip(craftZip([config])))
    }

    @Test func whatHumCantOpenIsNamed() {
        #expect(throws: ZipArchive.ReadError.unsupported("encrypted file 'secret.json'")) {
            try ZipArchive.read(craftZip([RawEntry(name: "secret.json", method: 0, data: json("{}"), flags: 1)]))
        }
        #expect(throws: ZipArchive.ReadError.unsupported("ZIP64")) {
            try ZipArchive.read(craftZip([RawEntry(name: "big.bin", method: 0, data: json("{}"), size: 0xFFFF_FFFF)]))
        }
        #expect(throws: ZipArchive.ReadError.unsupported("compression method 12 in 'a.bin'")) {
            try ZipArchive.read(craftZip([RawEntry(name: "a.bin", method: 12, data: json("{}"))]))
        }
    }

    @Test func changedBytesFailTheirCheck() {
        // Stored, but the two sizes disagree.
        #expect(throws: ZipArchive.ReadError.checksum("a.txt")) {
            try ZipArchive.read(craftZip([RawEntry(name: "a.txt", method: 0, data: json("hello"), size: 4)]))
        }
        // The right size, the wrong CRC.
        #expect(throws: ZipArchive.ReadError.checksum("a.txt")) {
            try ZipArchive.read(craftZip([RawEntry(name: "a.txt", method: 0, data: json("hello"), crc: 1)]))
        }
    }

    @Test func aCutOffFileSaysSo() {
        let zip = craftZip([config, RawEntry(name: "media/a.jpg", method: 0, data: Data(count: 500))])
        let end = zip.count - 22
        let central = Int(zip.u32(at: end + 16))

        var pastTheEnd = zip
        pastTheEnd.setU32(UInt32(zip.count), at: end + 16)  // the directory starts after the file ends
        #expect(throws: ZipArchive.ReadError.truncated) { try ZipArchive.read(pastTheEnd) }

        var noLocalHeader = zip
        noLocalHeader[0] = 0  // the first entry's header isn't one
        #expect(throws: ZipArchive.ReadError.truncated) { try ZipArchive.read(noLocalHeader) }

        var longerThanTheFile = zip
        let second = central + 46 + "hum.json".utf8.count
        longerThanTheFile.setU32(100_000, at: second + 20)
        longerThanTheFile.setU32(100_000, at: second + 24)
        #expect(throws: ZipArchive.ReadError.truncated) { try ZipArchive.read(longerThanTheFile) }

        // The directory says there are more files than it holds.
        var fewerThanItSays = zip
        fewerThanItSays.setU16(3, at: end + 10)
        #expect(throws: ZipArchive.ReadError.truncated) { try ZipArchive.read(fewerThanItSays) }
    }

    @Test func foldersInsideAreSkipped() throws {
        let zip = craftZip([RawEntry(name: "media/", method: 0, data: Data()), config])
        #expect(try ZipArchive.read(zip).map(\.path) == ["hum.json"])
    }

    /// A received file is read in place, so its bytes may not start at index 0.
    @Test func bytesInTheMiddleOfOthersOpen() throws {
        let entries = [ZipArchive.Entry(path: "hum.json", data: json("{}"))]
        let padded = Data([1, 2, 3]) + ZipArchive.write(entries)
        #expect(try ZipArchive.read(padded.dropFirst(3)) == entries)
    }

    /// The app stops reading a file the parent no longer wants: between entries, as a cancellation, not
    /// as a damaged file.
    @Test func readingStopsWhenCancelled() async {
        let zip = ZipArchive.write([.init(path: "hum.json", data: json("{}")), .init(path: "media/a.jpg", data: Data([1]))])
        let read = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ZipArchive.read(zip)
        }
        await #expect(throws: CancellationError.self) { try await read.value }
        let open = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try HumPackage.read(zip)
        }
        await #expect(throws: CancellationError.self) { try await open.value }
    }

    // MARK: Limits are inclusive

    @Test func exactlyTheMostFilesPassesTheCount() {
        var zip = craftZip([config])
        zip.setU16(UInt16(ZipArchive.maxEntries), at: zip.count - 22 + 10)
        // Not refused as too many: it fails later, because the directory holds only one.
        #expect(throws: ZipArchive.ReadError.truncated) { try ZipArchive.read(zip) }
    }

    @Test func theTightestPackingIsAllowed() {
        let packed = Data(count: 10)
        let tightest = 10 * ZipArchive.maxRatio + 1024
        let error = #expect(throws: ZipArchive.ReadError.self) {
            try ZipArchive.read(craftZip([RawEntry(name: "a.bin", method: 8, data: packed, size: tightest)]))
        }
        // Not too big: the bytes just aren't real compressed data.
        #expect(error == .unsupported("damaged compressed data"))
        #expect(throws: ZipArchive.ReadError.tooBig) {
            try ZipArchive.read(craftZip([RawEntry(name: "a.bin", method: 8, data: packed, size: tightest + 1)]))
        }
    }

    @Test func exactlyTheLargestTotalIsAllowed() {
        // Six entries that together unpack to exactly the limit. They share their bytes, so reading stops
        // there, before anything is unpacked.
        let each = ZipArchive.maxTotalSize / 6
        #expect(each * 6 == ZipArchive.maxTotalSize)
        var entries = (0..<6).map { RawEntry(name: "media/\($0).jpg", method: 8, data: Data(count: 100_000), size: each) }
        #expect(throws: ZipArchive.ReadError.unsupported("overlapping files")) {
            try ZipArchive.read(craftZip(entries, sameOffset: true))
        }
        entries[5].size += 1
        #expect(throws: ZipArchive.ReadError.tooBig) { try ZipArchive.read(craftZip(entries, sameOffset: true)) }
    }

    @Test func theTooBigMessageNamesTheLimit() {
        #expect(PackageProblem.tooBig.text.contains("\(ZipArchive.maxTotalSize / 1024 / 1024) MB"))
    }

    // MARK: Packages

    @Test func aDamagedPackageSaysSo() {
        #expect(throws: HumConfigError.badPackage(.damaged)) {
            try HumPackage.read(craftZip([RawEntry(name: "hum.json", method: 0, data: json("{}"), crc: 1)]))
        }
        #expect(throws: HumConfigError.badPackage(.damaged)) {
            try HumPackage.read(craftZip([RawEntry(name: "hum.json", method: 0, data: json("{}"), flags: 1)]))
        }
    }

    /// Finder puts everything in one folder when it zips a folder.
    @Test func aPackageInOneFolderOpens() throws {
        let zip = ZipArchive.write([
            .init(path: "Boards/hum.json", data: json("{}")),
            .init(path: "Boards/media/a.jpg", data: Data([1])),
            .init(path: "Boards/CREDITS.txt", data: json("credits")),
            .init(path: "Boards/media/../../evil.jpg", data: Data([2])),
        ])
        let contents = try HumPackage.read(zip)
        #expect(contents.json == json("{}"))
        #expect(contents.media == ["media/a.jpg": Data([1])])
        #expect(contents.credits == json("credits"))
        // Two folders deep isn't looked in.
        #expect(throws: HumConfigError.badPackage(.noConfig)) {
            try HumPackage.read(ZipArchive.write([.init(path: "a/b/hum.json", data: json("{}"))]))
        }
    }
}

extension Data {
    mutating func setU16(_ value: UInt16, at i: Int) {
        self[i] = UInt8(value & 0xFF)
        self[i + 1] = UInt8(value >> 8)
    }

    mutating func setU32(_ value: UInt32, at i: Int) {
        for k in 0..<4 { self[i + k] = UInt8(value >> (8 * UInt32(k)) & 0xFF) }
    }
}
