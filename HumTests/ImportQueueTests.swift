// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import HumConfig
@testable import Hum

/// Changes queued by Shortcuts and Siri wait for a parent, then show one at a time through the same
/// check and preview as any file. A broken or cancelled one never blocks the rest.
@MainActor
@Suite("Import: the Shortcuts queue")
struct ImportQueueTests {
    /// A model with its own queue folder, so tests running at the same time don't share one.
    func makeQueueModel() throws -> (AppModel, URL) {
        let model = makeModel()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Pending-\(UUID().uuidString)", isDirectory: true)
        model.pendingChangesFolder = folder
        return (model, folder)
    }

    /// One new board, as hum.json.
    func change(_ name: String) throws -> Data {
        try HumDocument(boards: [HumBoard(name: name, rows: 1, columns: 2, tiles: [
            HumTile(label: name, spokenText: "Let's go to the \(name)!", row: 0, column: 0)])]).encodedJSON()
    }

    @Test func changesWaitForAParentThenShowOneAtATime() async throws {
        let (model, folder) = try makeQueueModel()
        defer { try? FileManager.default.removeItem(at: folder) }
        try PendingChanges.enqueue(try change("park"), name: "a park.json", in: folder)
        try PendingChanges.enqueue(try change("zoo"), name: "b zoo.json", in: folder)

        model.showNextPendingChange()
        #expect(model.importStage == nil, "nothing shows to the child")

        model.mode = .parent
        #expect(model.checkingImport?.fileName == "a park.json")
        await model.waitForImportCheck()
        let first = try #require(model.pendingImport)
        #expect(first.fileName == "a park.json")
        #expect(first.queueFile != nil)
        #expect(first.merge.summary.newBoards == 1)

        // The parent decides (or cancels): that one is done, and the next one is checked.
        model.pendingImport = nil
        #expect(PendingChanges.all(in: folder).count == 1)
        await model.waitForImportCheck()
        #expect(model.pendingImport?.fileName == "b zoo.json")
        model.pendingImport = nil
        #expect(PendingChanges.all(in: folder).isEmpty)
        #expect(model.importStage == nil)
    }

    @Test func aBrokenChangeIsDroppedAndTheNextShows() async throws {
        let (model, folder) = try makeQueueModel()
        defer { try? FileManager.default.removeItem(at: folder) }
        try PendingChanges.enqueue(Data("not a Hum file".utf8), name: "a broken.json", in: folder)
        try PendingChanges.enqueue(try change("zoo"), name: "b zoo.json", in: folder)

        model.mode = .parent
        await model.waitForImportCheck()
        #expect(model.pendingImport?.fileName == "b zoo.json")
        #expect(model.importError == nil, "a queued change that can't be read is dropped quietly")
        #expect(PendingChanges.all(in: folder).map(PendingChanges.displayName) == ["b zoo.json"])
    }

    @Test func cancellingAChangeWhileItsCheckedShowsTheNext() async throws {
        let (model, folder) = try makeQueueModel()
        defer { try? FileManager.default.removeItem(at: folder) }
        try PendingChanges.enqueue(try change("park"), name: "a park.json", in: folder)
        try PendingChanges.enqueue(try change("zoo"), name: "b zoo.json", in: folder)

        model.mode = .parent
        #expect(model.checkingImport?.fileName == "a park.json")
        model.cancelImportCheck()
        #expect(model.checkingImport?.fileName == "b zoo.json")
        await model.waitForImportCheck()
        #expect(model.pendingImport?.fileName == "b zoo.json")
        #expect(PendingChanges.all(in: folder).count == 1)
    }

    /// A file the parent opened is already showing: a queued change waits behind it.
    @Test func aQueuedChangeWaitsBehindAnOpenPreview() async throws {
        let (model, folder) = try makeQueueModel()
        defer { try? FileManager.default.removeItem(at: folder) }
        model.mode = .parent
        model.requestImport(data: try change("beach"), fileName: "beach.json")
        await model.waitForImportCheck()
        try PendingChanges.enqueue(try change("zoo"), name: "zoo.json", in: folder)
        model.showNextPendingChange()
        #expect(model.pendingImport?.fileName == "beach.json")
        #expect(model.checkingImport == nil)
    }
}

/// The import checks a parent meets when a file can't be used, and what cancelling does.
@MainActor
@Suite("Import: checks and cancelling")
struct ImportCheckTests {
    @Test func aFileThatIsGoneSaysSo() async {
        let model = makeModel()
        model.requestImport(url: FileManager.default.temporaryDirectory.appendingPathComponent("gone \(UUID().uuidString).hum"))
        await model.waitForImportCheck()
        #expect(model.importError == friendlyMessage(for: HumConfigError.badPackage(.unreadable)))
        #expect(model.pendingImport == nil)
    }

    /// A file from a nearby device goes through the same checks as one opened from Files.
    @Test func aBadFileFromANearbyDeviceSaysWhy() async {
        let model = makeModel()
        model.requestImport(data: Data(#"{"formatVersion": 99, "boards": []}"#.utf8), fileName: "future.hum")
        #expect(model.checkingImport?.fileName == "future.hum")
        await model.waitForImportCheck()
        #expect(model.importError == friendlyMessage(for: HumConfigError.newerFormat(found: 99, supported: 1)))
        #expect(model.checkingImport != nil, "the Checking… sheet stays to say why")
    }

    @Test func aNewFileClearsAnOldError() async throws {
        let model = makeModel()
        model.requestImport(data: Data("nope".utf8), fileName: "nope.hum")
        await model.waitForImportCheck()
        #expect(model.importError != nil)
        let good = try HumDocument(boards: [HumBoard(name: "Park", rows: 1, columns: 2, tiles: [])]).encodedJSON()
        model.requestImport(data: good, fileName: "park.json")
        #expect(model.importError == nil)
        await model.waitForImportCheck()
        #expect(model.pendingImport?.fileName == "park.json")
    }

    @Test func checkingStopsWhenCancelled() async throws {
        let model = makeModel()
        let data = try HumDocument(boards: [HumBoard(name: "Park", rows: 1, columns: 2, tiles: [])]).encodedJSON()
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ImportService(model: model).prepare(data: data, fileName: "park.json")
        }
        await #expect(throws: CancellationError.self) { try await work.value }
    }

    @Test func checkingAndPreviewShareOneSheet() {
        let check = ImportCheck(fileName: "Trains.hum")
        #expect(ImportStage.checking(check).id == check.id)
        #expect(ImportService.folderName(for: "Express2-v2.hum") == "Express2-v2")
        #expect(ImportService.folderName(for: "hum.json") == "hum")
        #expect(throws: HumConfigError.badPackage(.unreadable)) {
            try ImportService.read(URL(fileURLWithPath: "/no/such/file.hum"))
        }
    }
}
