// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import Hum

/// A tile never moves on its own. Only an explicit parent move changes positions.
@MainActor
@Suite("Motor-plan stability")
struct MotorPlanTests {
    @Test func addingATileShiftsNothing() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        try model.store.addTile(to: model.home, row: 3, column: 3, label: "new", spokenText: "All aboard!")
        var after = model.layout(model.home)
        #expect(after.removeValue(forKey: "3,3") == "new")
        #expect(after == before)
    }

    @Test func addingToATakenSpotIsRefused() throws {
        let model = makeModel()
        #expect(throws: StoreError.slotTaken) {
            try model.store.addTile(to: model.home, row: 0, column: 0, label: "x", spokenText: "x")
        }
    }

    @Test func hidingKeepsTheSlotAndShiftsNothing() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let tile = try #require(model.home.placedTiles.first { $0.label == "snack" })
        model.store.setHidden(tile, true)
        #expect(model.layout(model.home) == before)  // still placed, same spot
        model.rebuildSnapshot()
        #expect(model.snapshot?.cells[tile.row!][tile.column!] == nil)  // the child sees an empty space
    }

    @Test func deletingLeavesAnEmptySpotOnly() throws {
        let model = makeModel()
        var before = model.layout(model.home)
        let tile = try #require(model.home.placedTiles.first { $0.label == "play" })
        let key = "\(tile.row!),\(tile.column!)"
        model.store.delete(tile)
        before.removeValue(forKey: key)
        #expect(model.layout(model.home) == before)
    }

    @Test func explicitMoveSwapsTwoTilesOnly() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let hi = try #require(model.home.placedTiles.first { $0.label == "hi" })
        model.store.move(hi, to: 0, column: 1, on: model.home)  // onto "bye-bye"
        let after = model.layout(model.home)
        #expect(after["0,1"] == "hi")
        #expect(after["0,0"] == "bye-bye")
        #expect(after.filter { !["0,0", "0,1"].contains($0.key) } == before.filter { !["0,0", "0,1"].contains($0.key) })
    }

    @Test func growingTheGridMovesNothing() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        try model.store.resize(model.home, rows: 6, columns: 6)
        #expect(model.layout(model.home) == before)
    }

    @Test func shrinkingIsRefusedWhenTilesWouldBeCutOff() throws {
        let model = makeModel()
        #expect(throws: (any Error).self) { try model.store.resize(model.home, rows: 3, columns: 4) }
        #expect(model.home.rows == 5)
    }

    /// Labels in reading order (left to right, top to bottom).
    func readingOrder(_ board: Board) -> [String] {
        board.placedTiles.sorted { ($0.row!, $0.column!) < ($1.row!, $1.column!) }.map(\.label)
    }

    /// Bigger tiles (fewer across) re-flow in reading order: same order, more rows, nothing in the tray.
    @Test func fewerColumnsKeepsTheOrderAndAddsRows() throws {
        let model = makeModel()
        let order = readingOrder(model.home)
        model.store.setColumns(model.home, 3)
        #expect(model.home.columns == 3)
        #expect(readingOrder(model.home) == order)
        #expect(model.home.unplacedTiles.isEmpty)
        #expect(model.home.placedTiles.allSatisfy { $0.row! < model.home.rows && $0.column! < 3 })
    }

    /// Smaller tiles re-flow the same way, and one Undo puts every tile back.
    @Test func moreColumnsKeepsTheOrderAndUndoes() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let order = readingOrder(model.home)
        model.store.setColumns(model.home, 6)
        #expect(readingOrder(model.home) == order)
        model.store.undo()
        #expect(model.layout(model.home) == before)
        #expect(model.home.columns == 4)
    }

    /// The editor's spare row: a tile added there makes the board one row taller, in the same undo step.
    @Test func addingInTheSpareRowGrowsTheBoard() throws {
        let model = makeModel()
        #expect(BoardStore.editorRows(model.home) == 6)
        try model.store.addTile(to: model.home, row: 5, column: 0, label: "new", spokenText: "New one")
        #expect(model.home.rows == 6)
        #expect(BoardStore.editorRows(model.home) == 7)
        model.store.undo()
        #expect(model.home.rows == 5)
    }

    /// Dragging a tile into the spare row moves only that tile and grows the board.
    @Test func movingIntoTheSpareRowGrowsTheBoard() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let hi = try #require(model.home.placedTiles.first { $0.label == "hi" })
        model.store.move(hi, to: 5, column: 2, on: model.home)
        #expect(model.home.rows == 6)
        #expect(hi.row == 5 && hi.column == 2)
        #expect(model.layout(model.home).filter { $0.value != "hi" } == before.filter { $0.value != "hi" })
    }

    @Test func undoRestoresAMove() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let hi = try #require(model.home.placedTiles.first { $0.label == "hi" })
        model.store.move(hi, to: 3, column: 3, on: model.home)
        #expect(model.layout(model.home) != before)
        model.store.undo()
        #expect(model.layout(model.home) == before)
    }

    @Test func protestTilesAreOnHomeAtFullSize() throws {
        let model = makeModel()
        model.rebuildSnapshot()
        let cells = model.snapshot!.cells.joined().compactMap { $0 }
        for phrase in ["No thank you", "Stop!", "All done", "I need a break", "Too loud", "Help me"] {
            #expect(cells.contains { $0.spokenText == phrase })
        }
    }
}
