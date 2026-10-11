// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData
import HumConfig

/// Every parent edit goes through here. It enforces the motor-plan rules and makes every change undoable.
///
/// - Only `move` changes a tile's position (and stamps `positionUpdatedAt`).
/// - Adding, hiding and deleting never shift other tiles.
/// - A board can only shrink if no tile would be cut off.
@MainActor
final class BoardStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        if context.undoManager == nil { context.undoManager = UndoManager() }
    }

    var undoManager: UndoManager? { context.undoManager }

    /// Runs `body` as one undo step named `name` ("Undo Add Tile") and saves.
    func change(_ name: String, _ body: () throws -> Void) rethrows {
        undoManager?.beginUndoGrouping()
        defer {
            // Save *inside* the group: SwiftData records undo steps when it processes changes, so a
            // save after closing the group would put this change into some other undo step.
            try? context.save()
            undoManager?.setActionName(name)
            undoManager?.endUndoGrouping()
        }
        try body()
    }

    /// Forgets all undo steps (after first-run setup, so the starter board can't be undone away).
    func clearUndo() {
        undoManager?.removeAllActions()
    }

    func undo() {
        guard let undoManager, undoManager.canUndo else { return }
        undoManager.undo()
        try? context.save()
    }

    // MARK: Queries

    func boards() -> [Board] {
        (try? context.fetch(FetchDescriptor<Board>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func board(_ id: UUID) -> Board? { boards().first { $0.id == id } }

    func tile(on board: Board, row: Int, column: Int) -> Tile? {
        board.placedTiles.first { $0.row == row && $0.column == column }
    }

    // MARK: Tiles

    /// Adds a tile to an empty slot. Throws if the slot is taken (callers only offer empty slots).
    @discardableResult
    func addTile(to board: Board, row: Int, column: Int, label: String, spokenText: String) throws -> Tile {
        guard tile(on: board, row: row, column: column) == nil else { throw StoreError.slotTaken }
        let tile = Tile(label: label, spokenText: spokenText, row: row, column: column)
        change("Add Tile") {
            context.insert(tile)
            tile.board = board
            board.updatedAt = .now
        }
        return tile
    }

    /// Moves a tile to a slot. If another tile is there, the two swap. Both moves are explicit parent actions.
    func move(_ tile: Tile, to row: Int, column: Int, on board: Board) {
        guard row >= 0, column >= 0, row < board.rows, column < board.columns else { return }
        if tile.row == row && tile.column == column && tile.board?.id == board.id { return }
        change("Move Tile") {
            let now = Date.now
            if let other = self.tile(on: board, row: row, column: column), other.id != tile.id {
                if tile.board?.id == board.id, let fromRow = tile.row, let fromColumn = tile.column {
                    other.row = fromRow
                    other.column = fromColumn
                } else {
                    // Coming from the "needs a spot" tray or another board: the other tile has nowhere
                    // to go, so it becomes unplaced instead of being pushed somewhere else.
                    other.row = nil
                    other.column = nil
                }
                other.positionUpdatedAt = now
            }
            tile.row = row
            tile.column = column
            tile.board = board
            tile.positionUpdatedAt = now
        }
    }

    func setHidden(_ tile: Tile, _ hidden: Bool) {
        change(hidden ? "Hide Tile" : "Show Tile") {
            tile.isHidden = hidden
            tile.updatedAt = .now
        }
    }

    /// Deletes a tile. Its slot simply becomes empty; nothing else moves.
    func delete(_ tile: Tile) {
        change("Delete Tile") { context.delete(tile) }
    }

    /// Saves edits from the tile editor as one undo step.
    func update(_ tile: Tile, _ edit: (Tile) -> Void) {
        change("Edit Tile") {
            edit(tile)
            tile.updatedAt = .now
            tile.board?.updatedAt = .now
        }
    }

    // MARK: Boards

    @discardableResult
    func createBoard(name: String, rows: Int, columns: Int) -> Board {
        let board = Board(name: name, rows: rows, columns: columns, isHome: boards().isEmpty)
        change("New Board") { context.insert(board) }
        return board
    }

    func rename(_ board: Board, to name: String) {
        change("Rename Board") {
            board.name = name
            board.updatedAt = .now
        }
    }

    func setHome(_ board: Board) {
        change("Set Home Board") {
            for other in boards() { other.isHome = (other.id == board.id) }
        }
    }

    /// Copies a board with new IDs. Tiles keep the same positions as the original.
    @discardableResult
    func duplicate(_ board: Board) -> Board {
        let copy = Board(name: board.name + " copy", rows: board.rows, columns: board.columns)
        change("Duplicate Board") {
            context.insert(copy)
            for source in board.tiles ?? [] {
                let tile = Tile(label: source.label, spokenText: source.spokenText, row: source.row, column: source.column)
                context.insert(tile)
                tile.functionRaw = source.functionRaw
                tile.colorHex = source.colorHex
                tile.linkedBoardID = source.linkedBoardID
                tile.isHidden = source.isHidden
                tile.symbol = source.symbol
                tile.imageData = source.imageData
                tile.audioData = source.audioData
                tile.board = copy
            }
        }
        return copy
    }

    /// Deletes a board and its tiles. Tiles elsewhere that opened it keep speaking; their link is cleared.
    func delete(_ board: Board) throws {
        if board.isHome && boards().count > 1 { throw StoreError.cannotDeleteHome }
        change("Delete Board") {
            let id = board.id
            for tile in (try? context.fetch(FetchDescriptor<Tile>())) ?? [] where tile.linkedBoardID == id {
                tile.linkedBoardID = nil
            }
            context.delete(board)
        }
    }

    /// Tiles that would fall outside a smaller grid. Empty means the resize is safe.
    func tilesCutOff(_ board: Board, rows: Int, columns: Int) -> [Tile] {
        board.placedTiles.filter { ($0.row ?? 0) >= rows || ($0.column ?? 0) >= columns }
    }

    /// Changes the grid size. Growing never moves tiles.
    ///
    /// Shrinking is refused if it would cut tiles off, unless the parent explicitly agreed to
    /// `moveCutOffToTray`: then those tiles go to the "needs a spot" tray (they are not deleted, and no
    /// other tile moves). Every tile that stays keeps its exact row and column.
    func resize(_ board: Board, rows: Int, columns: Int, moveCutOffToTray: Bool = false) throws {
        let rows = min(max(rows, 1), HumValidator.rowRange.upperBound)
        let columns = min(max(columns, 1), HumValidator.columnRange.upperBound)
        guard rows * columns >= 2 else { throw StoreError.tooSmall }
        let cut = tilesCutOff(board, rows: rows, columns: columns)
        guard cut.isEmpty || moveCutOffToTray else { throw StoreError.wouldCutOff(cut.map(\.label)) }
        change("Change Grid Size") {
            let now = Date.now
            for tile in cut {
                tile.row = nil
                tile.column = nil
                tile.positionUpdatedAt = now
            }
            board.rows = rows
            board.columns = columns
            board.updatedAt = now
        }
    }

    /// Makes a new board and turns `tile` into a folder that opens it. One undo step.
    @discardableResult
    func makeFolder(named name: String, for tile: Tile, rows: Int, columns: Int) -> Board {
        let board = Board(name: name, rows: rows, columns: columns, isHome: false)
        change("New Folder") {
            context.insert(board)
            tile.linkedBoardID = board.id
            tile.updatedAt = .now
        }
        return board
    }
}

enum StoreError: LocalizedError, Equatable {
    case slotTaken
    case cannotDeleteHome
    case tooSmall
    case wouldCutOff([String])

    var errorDescription: String? {
        switch self {
        case .slotTaken: return "That spot already has a tile."
        case .cannotDeleteHome: return "This is the Home board. Choose another Home board first, then delete this one."
        case .tooSmall: return "A board needs at least 2 spots."
        case .wouldCutOff(let labels):
            let names = labels.prefix(3).map { "'\($0)'" }.joined(separator: ", ")
            return "The grid can't get smaller yet: \(names)\(labels.count > 3 ? " and others" : "") would not fit. Move or remove those tiles first, so nothing moves by itself."
        }
    }
}
