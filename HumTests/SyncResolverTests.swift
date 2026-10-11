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

    @Test func onlyOneHome() {
        let model = makeModel()
        let other = Board(name: "Other Home", rows: 2, columns: 2, isHome: true)
        other.createdAt = .now.addingTimeInterval(60)
        model.context.insert(other)
        SyncResolver.resolve(in: model.context)
        #expect(model.store.boards().filter(\.isHome).map(\.name) == ["Home"])
    }

    @Test func cleanStoreIsLeftAlone() {
        let model = makeModel()
        #expect(SyncResolver.resolve(in: model.context).isEmpty)
    }
}
