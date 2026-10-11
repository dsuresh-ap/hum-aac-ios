// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData

/// The phone layout: how a board too big for a phone screen is shown on iPhone.
///
/// A board keeps one grid (`rows` × `columns`) for iPad and Mac. On iPhone, a board wider than 4 columns
/// or taller than 8 rows is shown as pages of 4 × 8 instead. Each tile has its own phone spot
/// (`phonePage`, `phoneRow`, `phoneColumn`), so the phone has a stable motor plan of its own and resizing
/// or moving tiles on one kind of device never pushes tiles into the tray on the other.
///
/// - The first time a phone shows a board, tiles fill the pages in the board's reading order.
/// - Tiles that already have a phone spot keep it. New tiles take the first free spot.
/// - The bottom-right spot of every page is kept for "More", which opens the next page.
enum PhoneLayout {
    static let columns = 4
    static let rows = 8

    struct Spot: Hashable, Comparable {
        var page: Int
        var row: Int
        var column: Int

        static func < (a: Spot, b: Spot) -> Bool { (a.page, a.row, a.column) < (b.page, b.row, b.column) }
    }

    /// A board this small is shown as it is on a phone.
    static func fits(_ board: Board) -> Bool { board.columns <= columns && board.rows <= rows }

    /// The spot kept for "More" on every page.
    static func isMoreSpot(row: Int, column: Int) -> Bool { row == rows - 1 && column == columns - 1 }

    /// The tile's phone spot, if it has a valid one.
    static func spot(of tile: Tile) -> Spot? {
        guard let page = tile.phonePage, let row = tile.phoneRow, let column = tile.phoneColumn,
              page >= 0, (0..<rows).contains(row), (0..<columns).contains(column),
              !isMoreSpot(row: row, column: column) else { return nil }
        return Spot(page: page, row: row, column: column)
    }

    /// Phone pages the board uses (at least one).
    static func pageCount(_ board: Board) -> Int {
        (board.placedTiles.compactMap { spot(of: $0)?.page }.max() ?? 0) + 1
    }

    /// The tiles on one phone page, by spot.
    static func tiles(on board: Board, page: Int) -> [Spot: Tile] {
        var result: [Spot: Tile] = [:]
        for tile in board.placedTiles {
            if let spot = spot(of: tile), spot.page == page, result[spot] == nil { result[spot] = tile }
        }
        return result
    }

    /// The first free spot from `start` on, skipping the "More" spots.
    static func firstFreeSpot(on board: Board, from start: Spot = Spot(page: 0, row: 0, column: 0)) -> Spot {
        let taken = Set(board.placedTiles.compactMap(spot(of:)))
        var candidate = start
        while taken.contains(candidate) || isMoreSpot(row: candidate.row, column: candidate.column) {
            candidate.column += 1
            if candidate.column == columns { candidate.column = 0; candidate.row += 1 }
            if candidate.row == rows { candidate.row = 0; candidate.page += 1 }
        }
        return candidate
    }

    /// Gives every placed tile of `board` a phone spot. Tiles that have one keep it (if two claim the same
    /// spot, the one first in the board's reading order keeps it). The rest fill the first free spots, in
    /// the board's reading order. Not an undo step: it isn't a parent's edit. Returns true if anything changed.
    @discardableResult
    static func arrange(_ board: Board) -> Bool {
        let ordered = board.placedTiles.sorted { ($0.row ?? 0, $0.column ?? 0) < ($1.row ?? 0, $1.column ?? 0) }
        var taken = Set<Spot>()
        var waiting: [Tile] = []
        for tile in ordered {
            if let spot = spot(of: tile), taken.insert(spot).inserted { continue }
            waiting.append(tile)
        }
        guard !waiting.isEmpty else { return false }
        let undo = board.modelContext?.undoManager
        undo?.disableUndoRegistration()
        defer { undo?.enableUndoRegistration() }
        var next = Spot(page: 0, row: 0, column: 0)
        for tile in waiting {
            while taken.contains(next) || isMoreSpot(row: next.row, column: next.column) {
                next.column += 1
                if next.column == columns { next.column = 0; next.row += 1 }
                if next.row == rows { next.row = 0; next.page += 1 }
            }
            tile.phonePage = next.page
            tile.phoneRow = next.row
            tile.phoneColumn = next.column
            taken.insert(next)
        }
        return true
    }
}
