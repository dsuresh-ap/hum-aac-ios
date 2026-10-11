// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import HumConfig
@testable import Hum

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite("Config import/export through SwiftData")
struct ConfigAppTests {
    @Test func bundledStarterMatchesExamplesFile() throws {
        let bundled = try Data(contentsOf: try #require(Bundle.main.url(forResource: "starter.hum", withExtension: "json")))
        let example = try Data(contentsOf: repoRoot.appendingPathComponent("examples/starter.hum.json"))
        #expect(bundled == example, "Copy examples/starter.hum.json to hum-aac-ios/Resources/")
    }

    /// Golden test: the starter imports into SwiftData and exports back to equal JSON.
    @Test func starterRoundTripsThroughTheStore() throws {
        let model = makeModel()
        let original = try HumConfigLoader.load(Data(contentsOf: repoRoot.appendingPathComponent("examples/starter.hum.json"))).document
        let exported = ConfigBridge.export(boards: model.store.boards()).document
        #expect(exported.boards == original.boards)
    }

    @Test(arguments: ["food.hum.json", "linked-boards.hum.json"])
    func examplesRoundTripThroughTheStore(name: String) throws {
        let model = makeModel(starter: false)
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("examples/\(name)"))
        let pending = try ImportService(model: model).prepare(data: data, fileName: name)
        try ImportService(model: model).apply(pending, mode: .merge)
        let exported = ConfigBridge.export(boards: model.store.boards()).document
        let original = try HumConfigLoader.load(data).document
        #expect(Set(exported.boards.map(\.id)) == Set(original.boards.map(\.id)))
        for board in original.boards {
            #expect(exported.board(withID: board.id)?.tiles.sorted { $0.id.uuidString < $1.id.uuidString }
                    == board.tiles.sorted { $0.id.uuidString < $1.id.uuidString })
        }
    }

    @Test func mergeImportUpdatesTextButNeverMovesOrDeletes() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        var doc = ConfigBridge.export(boards: model.store.boards()).document
        doc.boards[0].tiles[0].spokenText = "Hello, friend!"
        doc.boards[0].tiles[0].row = 4; doc.boards[0].tiles[0].column = 3  // the file asks to move it
        doc.boards[0].tiles.removeLast()                                    // and drops a tile
        let pending = ImportService(model: model).prepare(loaded: LoadedConfig(document: doc), fileName: "edit")
        #expect(pending.merge.summary.sentence.contains("No tiles will move."))
        try ImportService(model: model).apply(pending, mode: .merge)
        #expect(model.layout(model.home) == before)
        #expect(model.home.placedTiles.contains { $0.spokenText == "Hello, friend!" })
    }

    @Test func importCanBeUndone() throws {
        let model = makeModel()
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("examples/food.hum.json"))
        let pending = try ImportService(model: model).prepare(data: data, fileName: "food")
        try ImportService(model: model).apply(pending, mode: .merge)
        #expect(model.store.boards().count == 2)
        model.store.undo()
        #expect(model.store.boards().count == 1)
    }

    @Test func unknownFieldsSurviveTheStore() throws {
        let model = makeModel()
        var doc = ConfigBridge.export(boards: model.store.boards()).document
        doc.boards[0].tiles[0].extra["fromTheFuture"] = .string("keep me")
        try ImportService(model: model).apply(ImportService(model: model).prepare(loaded: LoadedConfig(document: doc), fileName: "x"), mode: .merge)
        let exported = ConfigBridge.export(boards: model.store.boards()).document
        #expect(exported.boards[0].tiles.contains { $0.extra["fromTheFuture"] == .string("keep me") })
    }

    @Test func missingImageAndDeletedLinkNeverCrash() throws {
        let model = makeModel()
        let tile = try #require(model.home.placedTiles.first { $0.label == "snack" })
        tile.linkedBoardID = UUID()           // a board that doesn't exist
        tile.imageData = Data([1, 2, 3])      // not an image
        model.rebuildSnapshot()
        let cell = try #require(model.snapshot?.cells.joined().compactMap { $0 }.first { $0.id == tile.id })
        #expect(cell.linkedBoardExists == false)
        #expect(cell.image == nil)
        model.tap(cell, tapTime: 0)           // speaks, stays on Home
        #expect(model.snapshot?.isHome == true)
    }
}

@MainActor
@Suite("Folders and navigation")
struct NavigationTests {
    func modelWithFolders() throws -> (AppModel, Board, Board) {
        let model = makeModel()
        let snack = try #require(model.home.placedTiles.first { $0.label == "snack" })
        let food = model.store.makeFolder(named: "Food", for: snack, rows: 2, columns: 2)
        let fruit = try model.store.addTile(to: food, row: 0, column: 0, label: "fruit", spokenText: "")
        let fruitBoard = model.store.makeFolder(named: "Fruit", for: fruit, rows: 2, columns: 2)
        model.goHome()
        return (model, food, fruitBoard)
    }

    func cell(_ model: AppModel, _ label: String) throws -> BoardSnapshot.Cell {
        try #require(model.snapshot?.cells.joined().compactMap { $0 }.first { $0.label == label })
    }

    @Test func folderOpensAndBackReturns() throws {
        let (model, food, fruit) = try modelWithFolders()
        model.tap(try cell(model, "snack"), tapTime: 0)
        #expect(model.currentBoardID == food.id)
        model.tap(try cell(model, "fruit"), tapTime: 0)   // silent folder: opens without speaking
        #expect(model.currentBoardID == fruit.id)
        #expect(model.history.entries.map(\.spokenText) == ["Let's have a snack"])
        model.goBack()
        #expect(model.currentBoardID == food.id)
        model.goBack()
        #expect(model.snapshot?.isHome == true)
        #expect(!model.canGoBack)
    }

    @Test func homeClearsThePath() throws {
        let (model, _, _) = try modelWithFolders()
        model.tap(try cell(model, "snack"), tapTime: 0)
        model.tap(try cell(model, "fruit"), tapTime: 0)
        model.goHome()
        #expect(model.snapshot?.isHome == true)
        #expect(!model.canGoBack)
    }

    @Test func linkLoopsDontGrowThePath() throws {
        let (model, food, fruit) = try modelWithFolders()
        let back = try model.store.addTile(to: fruit, row: 0, column: 0, label: "food again", spokenText: "")
        back.linkedBoardID = food.id
        model.tap(try cell(model, "snack"), tapTime: 0)
        for _ in 0..<5 {
            model.tap(try cell(model, "fruit"), tapTime: 0)
            model.tap(try cell(model, "food again"), tapTime: 0)
        }
        #expect(model.currentBoardID == food.id)
        model.goBack()
        #expect(model.snapshot?.isHome == true)
    }

    @Test func returnHomeAfterFolderTapSetting() throws {
        let (model, _, _) = try modelWithFolders()
        model.settings.returnHomeAfterFolderTap = true
        model.tap(try cell(model, "snack"), tapTime: 0)
        try model.store.addTile(to: try #require(model.currentBoardID.flatMap(model.store.board)), row: 1, column: 1, label: "crackers", spokenText: "Let's have crackers!")
        model.rebuildSnapshot()
        model.tap(try cell(model, "crackers"), tapTime: 0)
        #expect(model.snapshot?.isHome == true)
    }
}

@MainActor
@Suite("History")
struct HistoryTests {
    @Test func fastRepeatsCollapseIntoOneEntry() throws {
        let history = SpeechHistory(fileURL: nil)
        let t = Date.now
        for i in 0..<20 { history.add(label: "uh oh", spokenText: "Uh oh!", function: .comment, colorHex: nil, at: t.addingTimeInterval(Double(i) * 0.1)) }
        history.add(label: "hi", spokenText: "Hi!", function: nil, colorHex: nil, at: t.addingTimeInterval(5))
        history.add(label: "uh oh", spokenText: "Uh oh!", function: .comment, colorHex: nil, at: t.addingTimeInterval(6))
        #expect(history.entries.map(\.count) == [20, 1, 1])
        #expect(history.recent(2).map(\.spokenText) == ["Uh oh!", "Hi!"])
    }

    @Test func historyIsCappedAndClearable() throws {
        let history = SpeechHistory(fileURL: nil)
        for i in 0..<(SpeechHistory.maxEntries + 50) {
            history.add(label: "\(i)", spokenText: "Phrase \(i)", function: nil, colorHex: nil, at: Date(timeIntervalSince1970: Double(i) * 100))
        }
        #expect(history.entries.count == SpeechHistory.maxEntries)
        history.clear()
        #expect(history.entries.isEmpty)
    }

    @Test func historyPersistsToDisk() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID()).json")
        let history = SpeechHistory(fileURL: url)
        history.add(label: "hi", spokenText: "Hi!", function: nil, colorHex: nil)
        try await Task.sleep(for: .seconds(1.5))
        #expect(SpeechHistory(fileURL: url).entries.map(\.spokenText) == ["Hi!"])
    }

    @Test func aiHelperKeepsQuotedGestaltsWhole() throws {
        #expect(AIHelper.quotedPhrases(in: "She says “all aboard!” and 'the end!' a lot") == ["all aboard!", "the end!"])
    }
}
