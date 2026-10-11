// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData

/// Repairs what iCloud sync can produce, without ever moving a tile on its own.
///
/// CloudKit merges each field "last edit wins", which keeps words and photos right, but two devices can
/// still disagree about *positions* (both put a new tile in the same empty spot while offline), or
/// both create the same record. This runs after every remote change. It is deterministic, so every
/// device reaches the same answer.
///
/// 1. Duplicate boards/tiles with the same `id`: keep the oldest record, delete the copies.
/// 2. More than one Home: a family's own Home beats Hum's starter board, then the newest Home wins
///    (so the latest import or setup is the one every device keeps). A device that joins sync uploads
///    the boards it already had, often just the starter; if that starter was never changed it holds
///    none of the family's work, so it is removed instead of lingering as a second "Home".
/// 3. Two tiles in one spot: the tile that has been there longer (older `positionUpdatedAt`, then
///    older `createdAt`, then smaller id) keeps the spot. The other goes to the "needs a spot" tray
///    for a parent to place. Nothing is pushed into another spot.
@MainActor
enum SyncResolver {
    struct Report: Equatable {
        var removedDuplicates = 0
        var fixedHomes = 0
        var removedStarterBoards = 0
        var unplacedTiles = 0
        var isEmpty: Bool { self == Report() }
    }

    @discardableResult
    static func resolve(in context: ModelContext) -> Report {
        var report = Report()
        let boards = (try? context.fetch(FetchDescriptor<Board>())) ?? []
        let tiles = (try? context.fetch(FetchDescriptor<Tile>())) ?? []

        // 1. Duplicates by stable id.
        for group in Dictionary(grouping: boards, by: \.id).values where group.count > 1 {
            let sorted = group.sorted(by: older)
            guard let kept = sorted.first else { continue }
            for copy in sorted.dropFirst() {
                // Move the copy's tiles to the kept board before deleting it, so nothing is lost.
                for tile in copy.tiles ?? [] { tile.board = kept }
                context.delete(copy)
                report.removedDuplicates += 1
            }
        }
        for group in Dictionary(grouping: tiles, by: \.id).values where group.count > 1 {
            for copy in group.sorted(by: older).dropFirst() {
                context.delete(copy)
                report.removedDuplicates += 1
            }
        }

        // 2. One Home.
        var liveBoards = ((try? context.fetch(FetchDescriptor<Board>())) ?? []).filter { !$0.isDeleted }
        let homes = liveBoards.filter(\.isHome).sorted(by: preferredHome)
        for extra in homes.dropFirst() {
            extra.isHome = false
            report.fixedHomes += 1
            if StarterBoard.isUntouched(extra) {
                for tile in extra.tiles ?? [] { context.delete(tile) }
                context.delete(extra)
                report.removedStarterBoards += 1
            }
        }
        liveBoards.removeAll { $0.isDeleted }

        // 3. One tile per spot. (No force-unwraps: this runs on data from other devices.)
        for board in liveBoards {
            var bySpot: [String: [Tile]] = [:]
            for tile in board.tiles ?? [] where !tile.isDeleted {
                guard let row = tile.row, let column = tile.column else { continue }
                if row >= board.rows || column >= board.columns || row < 0 || column < 0 {
                    // Outside the grid (another device shrank it with consent): wait in the tray.
                    tile.row = nil
                    tile.column = nil
                    report.unplacedTiles += 1
                } else {
                    bySpot["\(row),\(column)", default: []].append(tile)
                }
            }
            for group in bySpot.values where group.count > 1 {
                guard let keeper = group.sorted(by: keepsSpot).first else { continue }
                for loser in group where loser !== keeper {
                    loser.row = nil
                    loser.column = nil
                    report.unplacedTiles += 1
                }
            }
        }

        if !report.isEmpty { try? context.save() }
        return report
    }

    // Only synced values are compared, so every device makes the same choice.

    /// Which of two Homes stays Home: not the starter board, then the newest, then the smaller id.
    private static func preferredHome(_ a: Board, _ b: Board) -> Bool {
        let starterID = StarterBoard.homeID
        let (aStarter, bStarter) = (a.id == starterID, b.id == starterID)
        if aStarter != bStarter { return bStarter }
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    private static func older(_ a: Board, _ b: Board) -> Bool {
        (a.createdAt, a.updatedAt) < (b.createdAt, b.updatedAt)
    }

    private static func older(_ a: Tile, _ b: Tile) -> Bool {
        (a.createdAt, a.updatedAt) < (b.createdAt, b.updatedAt)
    }

    /// Who keeps a contested spot: whoever was placed there first.
    private static func keepsSpot(_ a: Tile, _ b: Tile) -> Bool {
        if a.positionUpdatedAt != b.positionUpdatedAt { return a.positionUpdatedAt < b.positionUpdatedAt }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }
}
