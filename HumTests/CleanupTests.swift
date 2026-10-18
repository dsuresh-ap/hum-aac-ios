// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import HumConfig
import Testing
@testable import Hum

/// Hum's temporary files (a child's boards, photos, a parent's voice) never linger, and only the newest
/// "Before import" backups are kept.
@MainActor
@Suite("Temporary files and backups")
struct CleanupTests {
    /// A folder of its own, so tests running at the same time don't see each other's files.
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CleanupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func make(_ name: String, in dir: URL, folder: Bool = false, age: TimeInterval = 0) throws -> URL {
        let url = dir.appendingPathComponent(name)
        if folder {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url.appendingPathComponent("inside.hum"))
        } else {
            try Data("x".utf8).write(to: url)
        }
        if age > 0 {
            try FileManager.default.setAttributes([.creationDate: Date.now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        return url
    }

    // MARK: Temporary files

    @Test func humsFilesAreRecognized() {
        #expect(HumTemporaryFiles.isHums("Export-\(UUID().uuidString)"))
        #expect(HumTemporaryFiles.isHums("Nearby-\(UUID().uuidString)"))
        #expect(HumTemporaryFiles.isHums("hum-recording.m4a"))
        #expect(HumTemporaryFiles.isHums("\(UUID().uuidString).m4a"))
        #expect(!HumTemporaryFiles.isHums("song.m4a"))
        #expect(!HumTemporaryFiles.isHums("com.apple.something"))
    }

    @Test func theLaunchSweepRemovesLeftoversButNothingInUse() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let oldExport = try make("Export-\(UUID().uuidString)", in: dir, folder: true, age: 3600)
        let oldNearby = try make("Nearby-\(UUID().uuidString)", in: dir, folder: true, age: 3600)
        let oldRecording = try make("hum-recording.m4a", in: dir, age: 3600)
        let oldDecode = try make("\(UUID().uuidString).m4a", in: dir, age: 3600)
        let notHums = try make("someone-else.txt", in: dir, age: 3600)
        let cutoff = Date.now.addingTimeInterval(-60)
        // Made by this run (after it started): in use, so it stays.
        let current = try make("Export-\(UUID().uuidString)", in: dir, folder: true)

        let removed = HumTemporaryFiles.sweep(createdBefore: cutoff, in: dir)

        for url in [oldExport, oldNearby, oldRecording, oldDecode] {
            #expect(!FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) left behind")
        }
        #expect(FileManager.default.fileExists(atPath: current.path))
        #expect(FileManager.default.fileExists(atPath: notHums.path))
        #expect(removed.count == 4)
    }

    @Test func aSharedFileIsGoneAfterSharing() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try SharedFile(data: Data(count: 1000), name: "Hum boards 2026-10-18.hum", in: dir)
        #expect(file.url.lastPathComponent == "Hum boards 2026-10-18.hum")
        #expect(FileManager.default.fileExists(atPath: file.url.path))
        // What the share sheet's completion (sent or cancelled) and its closing both do.
        file.remove()
        file.remove()
        #expect(!FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    // MARK: Backups

    @Test func onlyTheNewestBackupsAreKept() throws {
        let model = makeModel()
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        for day in 1...3 { _ = try make("Before import 2020-01-0\(day)T10-00-00Z.hum", in: dir) }

        try ImportService(model: model).writeBackup(in: dir)

        let names = ImportService.backups(in: dir).map(\.lastPathComponent)
        #expect(names.count == ImportService.backupsToKeep)
        #expect(ImportService.backupsToKeep == 3)
        #expect(!names.contains("Before import 2020-01-01T10-00-00Z.hum"), "the oldest goes")
        #expect(names.first?.hasPrefix("Before import 20") == true && names.first != "Before import 2020-01-03T10-00-00Z.hum",
                "the new one is kept")
    }

    @Test func extraBackupsArePrunedAtLaunch() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        for day in 1...9 { _ = try make("Before import 2020-01-0\(day)T10-00-00Z.hum", in: dir) }
        ImportService.pruneBackups(in: dir)
        #expect(ImportService.backups(in: dir).map(\.lastPathComponent) == [
            "Before import 2020-01-09T10-00-00Z.hum", "Before import 2020-01-08T10-00-00Z.hum",
            "Before import 2020-01-07T10-00-00Z.hum"])
    }

    @Test func deleteBackupsEmptiesTheFolderAndLeavesTheBoards() throws {
        let model = makeModel()
        let boardsBefore = model.store.boards().map(\.id)
        let tilesBefore = model.store.boards().flatMap(\.placedTiles).count
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try ImportService(model: model).writeBackup(in: dir)
        _ = try make("Before import 2020-01-01T10-00-00Z.hum", in: dir)
        #expect(ImportService.backupsSummary(in: dir).count == 2)
        #expect(ImportService.backupsSummary(in: dir).bytes > 0)

        try ImportService.deleteBackups(in: dir)

        #expect(ImportService.backupsSummary(in: dir).count == 0)
        #expect(ImportService.backupsSummary(in: dir).bytes == 0)
        #expect(model.store.boards().map(\.id) == boardsBefore)
        #expect(model.store.boards().flatMap(\.placedTiles).count == tilesBefore)
    }
}

extension CleanupTests {
    @Test func backupHelpersLeaveOtherFilesAlone() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let missing = dir.appendingPathComponent("No backups yet", isDirectory: true)
        #expect(ImportService.backups(in: missing).isEmpty)
        #expect(ImportService.backupsSummary(in: missing) == (0, 0))
        ImportService.pruneBackups(in: missing)
        try ImportService.deleteBackups(in: missing)

        let note = try make("notes.txt", in: dir)
        for day in 1...5 { _ = try make("Before import 2020-01-0\(day)T10-00-00Z.hum", in: dir) }
        ImportService.pruneBackups(in: dir)
        #expect(ImportService.backups(in: dir).count == ImportService.backupsToKeep)
        try ImportService.deleteBackups(in: dir)
        #expect(ImportService.backups(in: dir).isEmpty)
        #expect(FileManager.default.fileExists(atPath: note.path), "only backups are touched")
    }
}

/// The `.hum` file made for AirDrop and nearby devices.
@MainActor
@Suite("Files for sending")
struct SendingFileTests {
    @Test func theFileForSendingHasEverything() async throws {
        let model = makeModel()
        let data = try await ImportService(model: model).exportPackage()
        let loaded = try HumConfigLoader.load(data)
        #expect(Set(loaded.document.boards.map(\.id)) == Set(model.store.boards().map(\.id)))
        #expect(loaded.document.settings != nil)
        #expect(loaded.document == (try HumConfigLoader.load(ImportService(model: model).exportData())).document)
    }

    @Test func oneBoardOnItsOwn() async throws {
        let model = makeModel()
        let home = model.home
        let loaded = try HumConfigLoader.load(try await ImportService(model: model).exportPackage(boardID: home.id))
        #expect(loaded.document.boards.map(\.id) == [home.id])
        #expect(loaded.document.settings == nil, "settings go only with the whole setup")
    }

    /// The parent changed their mind while the file was being made: the screen drops it.
    @Test func makingTheFileCanBeCancelled() async {
        let model = makeModel()
        let making = Task { try await ImportService(model: model).exportPackage() }
        making.cancel()
        await #expect(throws: CancellationError.self) { try await making.value }
    }

    /// HUM-054: a tall board's file opens again (a tile in its last row).
    @Test func aTallBoardsFileOpensAgain() async throws {
        let model = makeModel()
        let home = model.home
        try model.store.resize(home, rows: 20, columns: home.columns)
        _ = try model.store.addTile(to: home, row: 19, column: 0, label: "bottom", spokenText: "All the way down!")
        let loaded = try HumConfigLoader.load(try await ImportService(model: model).exportPackage())
        let tile = loaded.document.boards.first(where: \.isHome)?.tiles.first { $0.label == "bottom" }
        #expect(tile?.row == 19)
    }
}
