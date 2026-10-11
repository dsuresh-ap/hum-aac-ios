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
/// 2. More than one Home: the oldest Home board stays Home.
/// 3. Two tiles in one spot: the tile that has been there longer (older `positionUpdatedAt`, then
///    older `createdAt`, then smaller id) keeps the spot. The other goes to the "needs a spot" tray
///    for a parent to place. Nothing is pushed into another spot.
@MainActor
enum SyncResolver {
    struct Report: Equatable {
        var removedDuplicates = 0
        var fixedHomes = 0
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
        let liveBoards = ((try? context.fetch(FetchDescriptor<Board>())) ?? []).filter { !$0.isDeleted }
        let homes = liveBoards.filter(\.isHome).sorted(by: older)
        for extra in homes.dropFirst() {
            extra.isHome = false
            report.fixedHomes += 1
        }

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
