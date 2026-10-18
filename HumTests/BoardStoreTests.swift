// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData
import Testing
@testable import Hum

/// Board edits not covered elsewhere: the tray, whole boards, re-flowing at the row limit, and what a
/// refused edit says. Each change is one undo step, and undo is checked on iOS 18 too (HUM-052).
@MainActor
@Suite("Board store")
struct BoardStoreTests {
    /// A tile waiting below the board, dropped on a taken spot: it takes the spot and the tile that was
    /// there waits below instead (nothing else is pushed). One Undo puts both back.
    @Test func aWaitingTileDroppedOnATakenSpot() throws {
        let model = makeModel()
        let home = model.home
        let waiting = Tile(label: "waiting", spokenText: "Wait for me!", row: nil, column: nil)
        model.context.insert(waiting)
        waiting.board = home
        try model.context.save()
        model.store.clearUndo()
        model.endEvent()
        let before = model.layout(home)
        let target = try #require(model.store.tile(on: home, row: 0, column: 0))

        model.store.move(waiting, to: 0, column: 0, on: home)
        model.endEvent()

        var expected = before
        expected["0,0"] = "waiting"
        #expect(model.layout(home) == expected)
        #expect(target.row == nil && target.column == nil)
        #expect(target.board?.id == home.id, "it waits below the same board")

        model.store.undo()
        #expect(model.layout(home) == before)
        #expect(waiting.row == nil && waiting.board?.id == home.id)
    }

    @Test func duplicatingABoardCopiesItAndUndoes() throws {
        let model = makeModel()
        let home = model.home
        let before = model.layout(home)
        let boardCount = model.store.boards().count
        model.endEvent()

        let copy = model.store.duplicate(home)
        model.endEvent()

        #expect(copy.name == "\(home.name) copy")
        #expect(!copy.isHome)
        #expect(model.layout(copy) == before, "same spots")
        #expect(Set(copy.placedTiles.map(\.id)).isDisjoint(with: home.placedTiles.map(\.id)), "new IDs")
        #expect(Set(copy.placedTiles.compactMap(\.linkedBoardID)) == Set(home.placedTiles.compactMap(\.linkedBoardID)))
        #expect(model.layout(home) == before)

        model.store.undo()
        #expect(model.store.boards().count == boardCount)
        #expect(model.layout(model.home) == before)
    }

    @Test func choosingAnotherHome() throws {
        let model = makeModel()
        let home = model.home
        let park = model.store.createBoard(name: "Park", rows: 2, columns: 2)
        model.endEvent()

        model.store.setHome(park)
        model.endEvent()
        #expect(model.store.boards().filter(\.isHome).map(\.id) == [park.id])
        model.goHome()
        #expect(model.snapshot?.boardID == park.id)

        model.store.undo()
        #expect(model.store.boards().filter(\.isHome).map(\.id) == [home.id])
    }

    /// Bigger tiles on a board whose last tile is in the last row: keeping the gaps would need more rows
    /// than a board can have, so the tiles close up, in the same order.
    @Test func reflowingClosesUpRatherThanPassTheRowLimit() throws {
        let model = makeModel(starter: false)
        let board = model.store.createBoard(name: "Tall", rows: 20, columns: 8)
        let first = try model.store.addTile(to: board, row: 0, column: 0, label: "first", spokenText: "First!")
        let last = try model.store.addTile(to: board, row: 19, column: 7, label: "last", spokenText: "Last!")

        model.store.setColumns(board, 4)

        #expect(board.columns == 4)
        #expect((first.row, first.column) == (0, 0))
        #expect((last.row, last.column) == (0, 1))
        #expect(board.rows == 1)
        #expect(board.unplacedTiles.isEmpty)
    }

    @Test func theSameTileSizeMovesNothing() throws {
        let model = makeModel()
        let home = model.home
        let before = model.layout(home)
        let (spots, rows) = model.store.reflowedSpots(home, columns: home.columns)
        #expect(spots.count == home.placedTiles.count)
        #expect(home.placedTiles.allSatisfy { spots[$0.id]?.row == $0.row && spots[$0.id]?.column == $0.column })
        #expect(rows == (home.placedTiles.compactMap(\.row).max() ?? -1) + 1)
        model.store.setColumns(home, home.columns)
        #expect(model.layout(home) == before)
    }

    @Test func refusedEditsSayWhy() {
        let two = StoreError.wouldCutOff(["snack", "park"]).errorDescription ?? ""
        #expect(two.contains("“snack”") && two.contains("“park”") && !two.contains("others"))
        let many = StoreError.wouldCutOff(["a", "b", "c", "d"]).errorDescription ?? ""
        #expect(many.contains("others") && !many.contains("“d”"), "three names at most")
        let all = [StoreError.slotTaken, .cannotDeleteHome, .tooSmall].compactMap(\.errorDescription)
        #expect(Set(all).count == 3)
    }

    /// Home can't be deleted while other boards are left (another board must be Home first). The last
    /// board can go: the child then sees "No board yet", and Undo brings it back with its tiles.
    @Test func homeGoesOnlyWhenItsTheLastBoard() throws {
        let model = makeModel()
        let home = model.home
        let before = model.layout(home)
        let park = model.store.createBoard(name: "Park", rows: 2, columns: 2)
        #expect(throws: StoreError.cannotDeleteHome) { try model.store.delete(home) }
        try model.store.delete(park)
        model.endEvent()

        try model.store.delete(home)
        model.endEvent()
        model.goHome()
        #expect(model.snapshot == nil)

        model.store.undo()
        model.goHome()
        #expect(model.snapshot?.isHome == true)
        #expect(model.layout(model.home) == before)
        #expect(throws: StoreError.tooSmall) { try model.store.resize(model.home, rows: 1, columns: 1) }
    }
}
