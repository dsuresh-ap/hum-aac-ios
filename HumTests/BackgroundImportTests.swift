// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import os
import Testing
import HumConfig
@testable import Hum

/// A file is read, unzipped, checked and planned off the main actor, so a big one never freezes the app
/// (or the child's board), and cancelling while it's checked changes nothing.
@MainActor
@Suite("Import in the background")
struct BackgroundImportTests {
    /// The starter's Home with one new tile in a free spot, as a .hum.
    func smallPackage(_ model: AppModel) throws -> Data {
        var doc = ConfigBridge.export(boards: model.store.boards()).document
        let home = try #require(doc.boards.firstIndex { $0.isHome })
        let spot = try #require(model.store.firstEmptySpot(on: model.home))
        doc.boards[home].tiles = [HumTile(label: "train", spokenText: "All aboard!", row: spot.row, column: spot.column)]
        return try HumPackage.write(doc, media: [:])
    }

    /// 40 boards of 48 tiles, each with a 1 MB picture: about 40 MB and 1,920 tiles.
    func bigPackage() throws -> Data {
        var boards: [HumBoard] = []
        var media: [String: Data] = [:]
        for b in 0..<40 {
            let path = "media/board\(b).jpg"
            media[path] = Data(repeating: UInt8(b), count: 1_000_000)
            let tiles = (0..<48).map { i in
                HumTile(label: "tile \(i)", spokenText: "Tile \(i) on board \(b)", row: i / 8, column: i % 8,
                        image: i == 0 ? path : nil)
            }
            boards.append(HumBoard(name: "Board \(b)", rows: 6, columns: 8, isHome: b == 0, tiles: tiles))
        }
        return try HumPackage.write(HumDocument(boards: boards), media: media)
    }

    @Test func theFileIsReadAndCheckedOffTheMainActor() async throws {
        let model = makeModel()
        let data = try smallPackage(model)
        let probe = ReadProbe()
        let work = Task { try await ImportService(model: model).prepare(fileName: "train.hum") { probe.read(data) } }
        // The read is held open, yet this main-actor loop keeps running: nothing waits on the main actor.
        #expect(await probe.waitUntilStarted())
        probe.release()
        let pending = try await work.value
        #expect(probe.ranOnMainThread == false)
        #expect(pending.merge.summary.newTiles == 1)
        #expect(pending.fileName == "train.hum")
    }

    @Test func aBigFileLeavesTheMainActorFree() async throws {
        let model = makeModel()
        let data = try bigPackage()
        let probe = ReadProbe(waits: false)
        let state = WorkState()
        let work = Task {
            defer { state.done = true }
            return try await ImportService(model: model).prepare(fileName: "big.hum") { probe.read(data) }
        }
        // Unzipping and checking 40 MB takes a while. If it ran on the main actor, this loop could never run
        // between the read starting and the check finishing. Other tests may hold the main actor too, so
        // this counts turns instead of timing them.
        var turnsWhileChecking = 0
        while !state.done {
            if probe.started { turnsWhileChecking += 1 }
            try await Task.sleep(for: .milliseconds(5))
        }
        let pending = try await work.value
        #expect(pending.merge.summary.newBoards == 40)
        #expect(turnsWhileChecking > 0, "the main actor was busy the whole time the file was checked")
    }

    @Test func aFileOpenedInHumShowsCheckingThenItsPreview() async throws {
        let model = makeModel()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Trains \(UUID().uuidString).hum")
        try smallPackage(model).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        model.requestImport(url: url)
        let check = try #require(model.checkingImport)
        #expect(model.importStage?.id == check.id)
        #expect(model.pendingImport == nil)

        await model.waitForImportCheck()
        #expect(model.checkingImport == nil)
        let pending = try #require(model.pendingImport)
        #expect(pending.id == check.id, "the sheet stays open from Checking… to the preview")
        #expect(pending.fileName == url.lastPathComponent)
        #expect(pending.merge.summary.newTiles == 1)
    }

    @Test func aBrokenFileSaysWhyAndChangesNothing() async throws {
        let model = makeModel()
        let before = ConfigBridge.export(boards: model.store.boards()).document
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("broken \(UUID().uuidString).hum")
        var damaged = try smallPackage(model)
        damaged.removeLast(30)
        try damaged.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        model.requestImport(url: url)
        await model.waitForImportCheck()
        #expect(model.pendingImport == nil)
        #expect(model.importError == friendlyMessage(for: HumConfigError.badPackage(.damaged)))
        #expect(model.checkingImport != nil, "the sheet stays open to say why")
        model.importError = nil
        model.cancelImportCheck()  // OK
        #expect(model.importStage == nil)
        #expect(ConfigBridge.export(boards: model.store.boards()).document == before)
    }

    @Test func cancellingWhileCheckingChangesNothing() async throws {
        let model = makeModel()
        model.mode = .parent
        let before = ConfigBridge.export(boards: model.store.boards()).document
        let couldUndo = model.store.undoManager?.canUndo
        let data = try smallPackage(model)
        let probe = ReadProbe()
        model.checkImport(ImportCheck(fileName: "train.hum")) { service in
            try await service.prepare(fileName: "train.hum") { probe.read(data) }
        }
        #expect(await probe.waitUntilStarted())

        model.cancelImportCheck()
        #expect(model.importStage == nil, "the sheet closes at once")
        probe.release()
        await model.waitForImportCheck()

        #expect(model.pendingImport == nil)
        #expect(model.importError == nil)
        #expect(model.lastImport == nil)
        #expect(ConfigBridge.export(boards: model.store.boards()).document == before)
        #expect(model.store.undoManager?.canUndo == couldUndo)
    }

    @Test func aNewerFileReplacesOneStillBeingChecked() async throws {
        let model = makeModel()
        let data = try smallPackage(model)
        let probe = ReadProbe()
        model.checkImport(ImportCheck(fileName: "first.hum")) { service in
            try await service.prepare(fileName: "first.hum") { probe.read(data) }
        }
        #expect(await probe.waitUntilStarted())
        model.checkImport(ImportCheck(fileName: "second.hum")) { try await $0.prepare(data: data, fileName: "second.hum") }
        probe.release()
        await model.waitForImportCheck()
        #expect(model.pendingImport?.fileName == "second.hum")
        #expect(model.importError == nil)
    }
}

/// Stands in for reading a file: notes the thread it ran on, then (unless `waits` is false) waits until
/// the test lets it finish.
nonisolated final class ReadProbe: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (started: false, onMain: false))
    private let gate = DispatchSemaphore(value: 0)
    private let waits: Bool

    init(waits: Bool = true) { self.waits = waits }

    func read(_ data: Data) -> Data {
        state.withLock { $0 = (true, Thread.isMainThread) }
        // Never waits forever: if this ran on the main actor, the test fails instead of hanging.
        if waits { _ = gate.wait(timeout: .now() + 10) }
        return data
    }

    func release() { gate.signal() }

    var started: Bool { state.withLock { $0.started } }
    var ranOnMainThread: Bool { state.withLock { $0.onMain } }

    /// Polls from the main actor, which only works while the read runs somewhere else.
    @MainActor
    func waitUntilStarted() async -> Bool {
        for _ in 0..<2000 {
            if started { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}

@MainActor
final class WorkState {
    var done = false
}
