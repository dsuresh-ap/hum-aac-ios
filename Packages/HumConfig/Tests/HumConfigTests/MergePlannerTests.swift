// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import HumConfig

@Suite("Merge rules (motor-plan stability)")
struct MergePlannerTests {
    let homeID = UUID()
    let a = UUID(), b = UUID(), c = UUID()

    func existing() -> HumDocument {
        HumDocument(boards: [HumBoard(id: homeID, name: "Home", rows: 2, columns: 2, isHome: true, tiles: [
            HumTile(id: a, label: "stop", spokenText: "Stop!", row: 0, column: 0, function: .protest, image: "media/a.jpg"),
            HumTile(id: b, label: "more", spokenText: "I want more", row: 0, column: 1, function: .request),
        ])])
    }

    @Test func mergeUpdatesMatchingIDsWithoutMovingThem() {
        var incoming = existing()
        incoming.boards[0].tiles[1].spokenText = "Let's do it again!"
        incoming.boards[0].tiles[1].row = 1  // the file asks to move it, but merge never moves
        incoming.boards[0].tiles[0].image = nil  // a file without the photo must not erase it

        let plan = MergePlanner.plan(existing: existing(), incoming: incoming, mode: .merge)
        let tile = plan.result.boards[0].tiles.first { $0.id == b }!
        #expect(tile.spokenText == "Let's do it again!")
        #expect(tile.row == 0 && tile.column == 1)
        #expect(plan.result.boards[0].tiles.first { $0.id == a }?.image == "media/a.jpg")
        #expect(plan.summary.changedTiles == 1)
        #expect(plan.summary.movedTiles == 0)
        #expect(plan.summary.removedTiles == 0)
    }

    @Test func mergeNeverDeletes() {
        var incoming = existing()
        incoming.boards[0].tiles.removeAll()
        let plan = MergePlanner.plan(existing: existing(), incoming: incoming, mode: .merge)
        #expect(plan.result.boards[0].tiles.count == 2)
        #expect(plan.summary.sentence == "0 new tiles, 0 changed tiles, 0 removed. No tiles will move.")
    }

    @Test func newTileInFreeSpotIsPlaced() {
        var incoming = existing()
        incoming.boards[0].tiles.append(HumTile(id: c, label: "up", spokenText: "Up!", row: 1, column: 1))
        let plan = MergePlanner.plan(existing: existing(), incoming: incoming, mode: .merge)
        #expect(plan.result.boards[0].tile(atRow: 1, column: 1)?.id == c)
        #expect(plan.unplaced.isEmpty)
        #expect(plan.summary.sentence == "1 new tile, 0 changed tiles, 0 removed. No tiles will move.")
    }

    @Test func newTileInTakenSpotBecomesUnplacedAndNothingMoves() {
        var incoming = existing()
        incoming.boards[0].tiles.append(HumTile(id: c, label: "up", spokenText: "Up!", row: 0, column: 0))
        let plan = MergePlanner.plan(existing: existing(), incoming: incoming, mode: .merge)
        #expect(plan.result.boards[0].tile(atRow: 0, column: 0)?.id == a)
        #expect(plan.unplaced.map(\.tile.id) == [c])
        #expect(plan.summary.unplacedTiles == 1)
        #expect(plan.summary.sentence.contains("will need a spot"))
    }

    @Test func mergeGrowsGridButNeverShrinks() {
        var incoming = existing()
        incoming.boards[0].rows = 1
        incoming.boards[0].columns = 5
        let plan = MergePlanner.plan(existing: existing(), incoming: incoming, mode: .merge)
        #expect(plan.result.boards[0].rows == 2)
        #expect(plan.result.boards[0].columns == 5)
    }

    @Test func mergeKeepsExistingHome() {
        let incoming = HumDocument(boards: [HumBoard(name: "Other", rows: 1, columns: 2, isHome: true)])
        let plan = MergePlanner.plan(existing: existing(), incoming: incoming, mode: .merge)
        #expect(plan.result.boards.filter(\.isHome).map(\.id) == [homeID])
        #expect(plan.summary.newBoards == 1)
    }

    @Test func mergeIsIdempotent() {
        let plan = MergePlanner.plan(existing: existing(), incoming: existing(), mode: .merge)
        #expect(plan.result == existing())
        #expect(plan.summary == MergePlanner.Summary())
    }

    @Test func replaceReportsRemovalsAndMoves() {
        var incoming = existing()
        incoming.boards[0].tiles.removeFirst()          // remove "stop"
        incoming.boards[0].tiles[0].row = 1             // move "more"
        let plan = MergePlanner.plan(existing: existing(), incoming: incoming, mode: .replace)
        #expect(plan.summary.removedTiles == 1)
        #expect(plan.summary.movedTiles == 1)
        #expect(plan.summary.changedTiles == 0)
        #expect(plan.result == incoming)
    }
}
