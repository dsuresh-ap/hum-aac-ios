// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import SwiftData
@testable import Hum

/// What iCloud can produce when two devices edit offline, and how it's repaired without moving tiles.
@MainActor
@Suite("Sync conflicts")
struct SyncResolverTests {
    @Test func twoTilesInOneSpotTheEarlierOneStays() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        // Device A placed "a" at 3,3 first; device B placed "b" there later. Both arrive.
        let a = Tile(label: "a", spokenText: "All aboard!", row: 3, column: 3)
        a.positionUpdatedAt = .now.addingTimeInterval(-60)
        let b = Tile(label: "b", spokenText: "Choo choo!", row: 3, column: 3)
        model.context.insert(a); a.board = model.home
        model.context.insert(b); b.board = model.home
        let report = SyncResolver.resolve(in: model.context)
        #expect(report.unplacedTiles == 1)
        #expect(a.row == 3 && a.column == 3)
        #expect(b.row == nil)                                  // waits in "needs a spot"
        var after = model.layout(model.home)
        after.removeValue(forKey: "3,3")
        #expect(after == before)                               // nothing else moved
    }

    @Test func duplicateRecordsCollapseToOne() throws {
        let model = makeModel()
        let original = try #require(model.home.placedTiles.first { $0.label == "hi" })
        let copy = Tile(id: original.id, label: "hi", spokenText: "Hi!", row: original.row, column: original.column)
        copy.createdAt = original.createdAt.addingTimeInterval(5)
        model.context.insert(copy); copy.board = model.home
        SyncResolver.resolve(in: model.context)
        let all = try model.context.fetch(FetchDescriptor<Tile>()).filter { $0.id == original.id }
        #expect(all.count == 1)
    }

    /// A device joining sync uploads its untouched starter board, even one made before the family's own
    /// setup. The family's Home stays Home and the starter disappears (it holds none of their work).
    @Test func familysHomeBeatsAnUntouchedStarterWhichIsRemoved() throws {
        let model = makeModel()
        let starterID = try #require(StarterBoard.homeID)
        #expect(StarterBoard.isUntouched(model.home))
        let family = Board(name: "Maya's Home", rows: 2, columns: 2, isHome: true)
        family.createdAt = model.home.createdAt.addingTimeInterval(3600)
        model.context.insert(family)
        let report = SyncResolver.resolve(in: model.context)
        #expect(report.removedStarterBoards == 1)
        #expect(model.store.boards().filter(\.isHome).map(\.name) == ["Maya's Home"])
        #expect(!model.store.boards().contains { $0.id == starterID })
        #expect(try model.context.fetch(FetchDescriptor<Tile>()).isEmpty)
    }

    @Test func anEditedStarterLosesHomeButIsKept() throws {
        let model = makeModel()
        let starter = model.home
        try #require(starter.placedTiles.first).spokenText = "Let's go to Grandma's!"
        let family = Board(name: "Maya's Home", rows: 2, columns: 2, isHome: true)
        family.createdAt = starter.createdAt.addingTimeInterval(-3600)  // even when it's older
        model.context.insert(family)
        let report = SyncResolver.resolve(in: model.context)
        #expect(report.removedStarterBoards == 0)
        #expect(!starter.isHome && family.isHome)
        #expect(model.store.boards().contains { $0.id == starter.id })
    }

    /// Two of the family's own Homes (e.g. a "Replace everything" on one device while another was
    /// offline): the newest one, the latest setup, stays Home everywhere.
    @Test func newestOfTwoFamilyHomesWins() {
        let model = makeModel(starter: false)
        let older = Board(name: "Old Home", rows: 2, columns: 2, isHome: true)
        older.createdAt = .now.addingTimeInterval(-3600)
        let newer = Board(name: "New Home", rows: 2, columns: 2, isHome: true)
        model.context.insert(older)
        model.context.insert(newer)
        SyncResolver.resolve(in: model.context)
        #expect(model.store.boards().filter(\.isHome).map(\.name) == ["New Home"])
        #expect(model.store.boards().count == 2)
    }

    /// "Replace everything" on another device can delete the board the child is looking at.
    @Test func aBoardDeletedElsewhereSendsTheChildHome() throws {
        let model = makeModel()
        let folder = model.store.addFolder(named: "Food", on: model.home, rows: 2, columns: 2)
        model.goHome()
        model.open(boardID: folder.id)
        #expect(model.snapshot?.boardID == folder.id)
        model.context.delete(folder)
        try model.context.save()
        model.rebuildSnapshot()  // what a synced change triggers
        #expect(model.snapshot?.boardID == model.home.id)
        #expect(!model.canGoBack)
    }

    @Test func cleanStoreIsLeftAlone() {
        let model = makeModel()
        #expect(SyncResolver.resolve(in: model.context).isEmpty)
    }
}
