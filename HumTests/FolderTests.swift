// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import Hum

/// Making folders and moving tiles into them never moves any other tile.
@MainActor
@Suite("Folders")
struct FolderTests {
    @Test func newFolderTileIsOneUndoStep() throws {
        let model = makeModel()
        let boardsBefore = model.store.boards().count
        let spot = try #require(model.store.firstEmptySpot(on: model.home))
        let tile = model.store.addTile(to: model.home, row: spot.row, column: spot.column, newFolderName: "Snacks", rows: 2, columns: 3) {
            $0.label = "snacks"
        }
        let folder = try #require(tile.linkedBoardID.flatMap(model.store.board))
        #expect(folder.name == "Snacks" && folder.rows == 2 && folder.columns == 3)
        #expect(model.store.boards().count == boardsBefore + 1)
        model.store.undo()
        #expect(model.store.boards().count == boardsBefore)
        #expect(model.store.tile(on: model.home, row: spot.row, column: spot.column) == nil)
    }

    @Test func addFolderPutsItsTileInTheFirstEmptySpot() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let spot = try #require(model.store.firstEmptySpot(on: model.home))
        let folder = model.store.addFolder(named: "Park", on: model.home, rows: 3, columns: 3)
        let tile = try #require(model.store.tile(on: model.home, row: spot.row, column: spot.column))
        #expect(tile.linkedBoardID == folder.id)
        #expect(tile.label == "Park")
        #expect(tile.symbol == "🌳")
        for (key, label) in before { #expect(model.layout(model.home)[key] == label) }
    }

    @Test func movingIntoAFolderKeepsTheTileAndMovesNothingElse() throws {
        let model = makeModel()
        let folder = model.store.createBoard(name: "Food", rows: 2, columns: 2)
        let blocker = try model.store.addTile(to: folder, row: 0, column: 0, label: "x", spokenText: "X!")
        let tile = try #require(model.home.placedTiles.first { $0.label == "snack" })
        let (id, image) = (tile.id, Data([1, 2, 3]))
        tile.imageData = image
        let homeBefore = model.layout(model.home).filter { $0.value != "snack" }
        let snackSpot = try #require(model.layout(model.home).first { $0.value == "snack" }?.key)

        #expect(model.store.moveToBoard(tile, folder))
        #expect(tile.id == id && tile.imageData == image)
        #expect(tile.board?.id == folder.id)
        #expect(tile.row == 0 && tile.column == 1)          // first empty spot
        #expect(blocker.row == 0 && blocker.column == 0)    // untouched
        #expect(model.layout(model.home) == homeBefore)     // its old spot is just empty

        model.store.undo()
        #expect(tile.board?.id == model.home.id)
        #expect(model.layout(model.home)[snackSpot] == "snack")  // back in its own spot

        // Redo moves it again, and undo after redo still works (BUGS.md, HUM-052).
        model.store.undoManager?.redo()
        #expect(tile.board?.id == folder.id)
        #expect(tile.row == 0)
        #expect(tile.column == 1)
        #expect(blocker.board?.id == folder.id && blocker.column == 0)
        #expect(model.store.undoManager?.undoActionName == "Move to Folder")
        model.store.undo()
        #expect(tile.board?.id == model.home.id)
    }

    @Test func movingIntoAFullFolderWaitsInTheTray() throws {
        let model = makeModel()
        let folder = model.store.createBoard(name: "Tiny", rows: 1, columns: 2)
        try model.store.addTile(to: folder, row: 0, column: 0, label: "a", spokenText: "A")
        try model.store.addTile(to: folder, row: 0, column: 1, label: "b", spokenText: "B")
        let tile = try #require(model.home.placedTiles.first)
        #expect(!model.store.moveToBoard(tile, folder))
        #expect(folder.unplacedTiles.map(\.id) == [tile.id])
    }

    @Test func renamingAFolderTileRenamesItsFolder() throws {
        let model = makeModel()
        let folder = model.store.addFolder(named: "Snack", on: model.home, rows: 2, columns: 2)
        let tile = try #require(model.home.placedTiles.first { $0.linkedBoardID == folder.id })
        model.store.update(tile) { $0.label = "food" }
        #expect(folder.name == "Food")

        // Renaming the folder renames its tile too (BUGS.md, HUM-039).
        model.store.rename(folder, to: "Kitchen")
        #expect(tile.label == "Kitchen")

        // A folder the parent named differently from its tile keeps its own name.
        tile.label = "treats"
        model.store.update(tile) { $0.label = "eat" }
        #expect(folder.name == "Kitchen")
    }

    @Test func duplicateTakesTheFirstEmptySpotAndMovesNothing() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let original = try #require(model.home.placedTiles.first { $0.label == "snack" })
        original.audioData = Data([4, 5, 6])
        let spot = try #require(model.store.firstEmptySpot(on: model.home))
        let copy = try #require(model.store.duplicate(original))
        #expect(copy.id != original.id)
        #expect(copy.spokenText == original.spokenText && copy.audioData == original.audioData)
        #expect(copy.row == spot.row && copy.column == spot.column)
        for (key, label) in before { #expect(model.layout(model.home)[key] == label) }
        model.store.undo()
        #expect(model.layout(model.home) == before)
    }

    @Test func editorJumpsForgetTheFolderPath() throws {
        let model = makeModel()
        model.mode = .parent
        let folder = model.store.createBoard(name: "Food", rows: 2, columns: 2)
        model.openFolderInEditor(folder.id)
        #expect(model.editPath == [model.home.id])
        model.backInEditor()
        #expect(model.editingBoardID == model.home.id)
        model.openFolderInEditor(folder.id)
        model.editBoard(model.home.id)
        #expect(model.editPath.isEmpty)
    }
}
