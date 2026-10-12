// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import HumConfig
@testable import Hum

/// Fixes from the end-to-end bug pass (docs/testing/BUGS.md), checked against the real store.
@MainActor
@Suite("Bug fixes")
struct BugFixTests {
    /// HUM-002: Undo after deleting a tile brings it back in its spot, with its words and picture.
    @Test func undoBringsADeletedTileBack() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let up = try #require(model.home.placedTiles.first { $0.label == "up" })
        let (id, row, column) = (up.id, up.row, up.column)
        up.imageData = Data([1, 2, 3])
        model.endEvent()
        model.store.delete(up)
        #expect(model.layout(model.home).count == before.count - 1)
        model.endEvent()
        model.store.undo()
        #expect(model.layout(model.home) == before)
        let back = try #require(model.home.placedTiles.first { $0.id == id })
        #expect(back.row == row && back.column == column && back.imageData == Data([1, 2, 3]))
        // Redo deletes it again, and Undo brings it back again.
        model.endEvent()
        model.store.undoManager?.redo()
        #expect(model.layout(model.home).count == before.count - 1)
        model.endEvent()
        model.store.undo()
        #expect(model.layout(model.home) == before)
    }

    /// HUM-002: an edit, a delete, then Undo twice never reaches SwiftData's record of the old tile
    /// (it's gone; that would crash). The delete is undone, and older steps are forgotten.
    @Test func undoPastADeleteIsSafe() throws {
        let model = makeModel()
        let up = try #require(model.home.placedTiles.first { $0.label == "up" })
        let id = up.id
        model.store.update(up) { $0.spokenText = "Up up up!" }
        model.endEvent()
        model.store.delete(up)
        model.endEvent()
        model.store.undo()
        model.endEvent()
        #expect(model.store.undoManager?.canUndo == false)
        model.store.undo()
        #expect(model.home.placedTiles.first { $0.id == id }?.spokenText == "Up up up!")
    }

    /// HUM-002: Undo after deleting a folder brings back its tiles and the links that opened it.
    @Test func undoBringsADeletedFolderBack() throws {
        let model = makeModel()
        let snack = try #require(model.home.placedTiles.first { $0.label == "snack" })
        let food = model.store.makeFolder(named: "Food", for: snack, rows: 2, columns: 2)
        try model.store.addTile(to: food, row: 0, column: 0, label: "apple", spokenText: "Apple please")
        let foodID = food.id
        model.endEvent()
        try model.store.delete(food)
        #expect(model.store.board(foodID) == nil && snack.linkedBoardID == nil)
        model.endEvent()
        model.store.undo()
        let back = try #require(model.store.board(foodID))
        #expect(back.placedTiles.map(\.label) == ["apple"])
        #expect(snack.linkedBoardID == foodID)
    }

    /// HUM-038: Undo after "Replace everything" brings back the boards from before.
    @Test func undoAfterReplaceEverything() throws {
        let model = makeModel()
        let before = ConfigBridge.export(boards: model.store.boards()).document
        let file = HumDocument(boards: [HumBoard(name: "Home", rows: 2, columns: 2, isHome: true, tiles: [
            HumTile(label: "chat", spokenText: "Let's chat", row: 0, column: 0),
        ])])
        let pending = ImportService(model: model).prepare(loaded: LoadedConfig(document: file), fileName: "other.hum")
        try ImportService(model: model).apply(pending, mode: .replace, backupWritten: true)
        #expect(model.home.placedTiles.map(\.label) == ["chat"])
        model.endEvent()
        model.store.undo()
        #expect(ConfigBridge.export(boards: model.store.boards()).document.boards == before.boards)
        model.endEvent()
        model.store.undoManager?.redo()
        #expect(model.home.placedTiles.map(\.label) == ["chat"])
    }

    /// HUM-038: pictures converted after an import never sit on top of the undo stack.
    @Test func backgroundSavesAreNotUndoSteps() throws {
        let model = makeModel()
        let hi = try #require(model.home.placedTiles.first { $0.label == "hi" })
        let undoBefore = model.store.undoManager?.canUndo ?? false
        model.store.withoutUndo { hi.imageData = Data([9]) }
        #expect((model.store.undoManager?.canUndo ?? false) == undoBefore)
    }

    /// HUM-001: merging a file with its own Home adds a folder tile on your Home that opens it.
    @Test func mergedHomeIsReachable() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let file = HumDocument(boards: [HumBoard(name: "Home", rows: 2, columns: 2, isHome: true, tiles: [
            HumTile(label: "chat", spokenText: "Let's chat", row: 0, column: 0),
        ])])
        let pending = ImportService(model: model).prepare(loaded: LoadedConfig(document: file), fileName: "Express2.hum")
        try ImportService(model: model).apply(pending, mode: .merge)
        #expect(model.store.boards().filter { $0.name == "Home" }.count == 1)
        let folder = try #require(model.store.boards().first { $0.name == "Express2" })
        let opener = try #require(model.home.placedTiles.first { $0.linkedBoardID == folder.id })
        var after = model.layout(model.home)
        #expect(after.removeValue(forKey: "\(opener.row!),\(opener.column!)") == "Express2")
        #expect(after == before)
        #expect(model.lastImport?.folderID == folder.id)
    }

    /// HUM-004: importing from setup leaves the file's own Home as Home, and finishes setup.
    @Test func firstRunImportKeepsTheFilesHome() throws {
        let model = makeModel(starter: false)
        #expect(model.needsFirstRun)
        let file = HumDocument(boards: [HumBoard(name: "Our Home", rows: 2, columns: 2, isHome: true, tiles: [
            HumTile(label: "chat", spokenText: "Let's chat", row: 0, column: 0),
        ])])
        let pending = ImportService(model: model).prepare(loaded: LoadedConfig(document: file), fileName: "ours.hum")
        try ImportService(model: model).apply(pending, mode: .merge)
        #expect(!model.needsFirstRun)
        #expect(model.store.boards().map(\.name) == ["Our Home"])
        #expect(model.home.placedTiles.map(\.label) == ["chat"])
    }

    /// HUM-039: renaming a folder renames the tile that opens it (when it still had the old name).
    @Test func renamingAFolderRenamesItsTile() throws {
        let model = makeModel()
        let snack = try #require(model.home.placedTiles.first { $0.label == "snack" })
        snack.label = "Food"
        let food = model.store.makeFolder(named: "Food", for: snack, rows: 2, columns: 2)
        model.store.rename(food, to: "Food and drink")
        #expect(snack.label == "Food and drink")
    }

    /// HUM-040: a folder without Home's protest tiles is flagged before it becomes Home.
    @Test func protestTilesMissingFromANewHome() throws {
        let model = makeModel()
        let snack = try #require(model.home.placedTiles.first { $0.label == "snack" })
        let food = model.store.makeFolder(named: "Food", for: snack, rows: 2, columns: 2)
        let missing = model.store.protestTilesMissing(from: food)
        #expect(missing.contains("no thank you") && missing.contains("stop"))
        #expect(model.store.protestTilesMissing(from: model.home).isEmpty)
    }

    /// HUM-021: the history box reads "Said: Hi! Say it again.", not "Hi!.".
    @Test func historySentencesDontDoublePunctuation() {
        #expect(HistoryBoxSentence.make("Hi!") == "Hi!")
        #expect(HistoryBoxSentence.make("All done") == "All done.")
    }

    /// HUM-011: the import preview names folder tiles and doesn't repeat a label that is the phrase.
    @Test func previewLines() {
        #expect(ImportPreviewSheet.describe(HumTile(label: "Chat", spokenText: "", row: 0, column: 0, linkedBoardID: UUID())) == "Chat (opens a folder)")
        #expect(ImportPreviewSheet.describe(HumTile(label: "I need a break.", spokenText: "I need a break.", row: 0, column: 0)) == "“I need a break.”")
        #expect(ImportPreviewSheet.describe(HumTile(label: "snack", spokenText: "Let's have a snack", row: 0, column: 0)) == "snack: “Let's have a snack”")
    }
}
