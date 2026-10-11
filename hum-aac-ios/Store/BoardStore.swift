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

    /// Moves a tile in the phone layout. If another tile is there, the two swap. The big layout
    /// (`row`/`column`, used by iPad and Mac) is untouched, except that a tile coming from the tray or
    /// another board takes the first empty spot there. Returns false (and changes nothing) when it needs
    /// that spot and the board is full.
    @discardableResult
    func movePhone(_ tile: Tile, to spot: PhoneLayout.Spot, on board: Board) -> Bool {
        guard !PhoneLayout.isMoreSpot(row: spot.row, column: spot.column) else { return false }
        let needsBigSpot = tile.board?.id != board.id || tile.row == nil || tile.column == nil
        let bigSpot = needsBigSpot ? firstEmptySpot(on: board) : nil
        if needsBigSpot && bigSpot == nil { return false }
        if !needsBigSpot && PhoneLayout.spot(of: tile) == spot { return true }
        change("Move Tile") {
            let from = needsBigSpot ? nil : PhoneLayout.spot(of: tile)
            if let other = PhoneLayout.tiles(on: board, page: spot.page)[spot], other.id != tile.id {
                // Swap. A tile with nowhere to go gets a free spot the next time the phone shows the board.
                other.phonePage = from?.page
                other.phoneRow = from?.row
                other.phoneColumn = from?.column
            }
            if let bigSpot {
                tile.board = board
                tile.row = bigSpot.row
                tile.column = bigSpot.column
                tile.positionUpdatedAt = .now
            }
            tile.phonePage = spot.page
            tile.phoneRow = spot.row
            tile.phoneColumn = spot.column
            board.updatedAt = .now
        }
        return true
    }

    /// The first empty spot, reading left to right, top to bottom. Nil when the board is full.
    func firstEmptySpot(on board: Board) -> (row: Int, column: Int)? {
        let taken = Set(board.placedTiles.map { "\($0.row!),\($0.column!)" })
        for row in 0..<board.rows {
            for column in 0..<board.columns where !taken.contains("\(row),\(column)") { return (row, column) }
        }
        return nil
    }

    /// Moves a tile into another board (a folder), keeping its ID, photo and recording. Its old spot
    /// stays empty. It goes to the first empty spot there, or the "needs a spot" tray if the board is
    /// full. Nothing else moves. Returns true when it got a spot.
    @discardableResult
    func moveToBoard(_ tile: Tile, _ target: Board) -> Bool {
        guard tile.board?.id != target.id else { return tile.row != nil }
        let spot = firstEmptySpot(on: target)
        change("Move to Folder") {
            let now = Date.now
            tile.board?.updatedAt = now
            tile.board = target
            tile.row = spot?.row
            tile.column = spot?.column
            tile.phonePage = nil  // its phone spot was on the old board; it gets a new one there
            tile.phoneRow = nil
            tile.phoneColumn = nil
            tile.positionUpdatedAt = now
            target.updatedAt = now
        }
        return spot != nil
    }

    /// Copies a tile (new ID, same words, picture, recording and color) into the first empty spot of
    /// its board, or the "needs a spot" tray when the board is full. Nothing else moves.
    @discardableResult
    func duplicate(_ tile: Tile) -> Tile? {
        guard let board = tile.board else { return nil }
        let spot = firstEmptySpot(on: board)
        let copy = Tile(label: tile.label, spokenText: tile.spokenText, row: spot?.row, column: spot?.column)
        change("Duplicate Tile") {
            context.insert(copy)
            copy.functionRaw = tile.functionRaw
            copy.colorHex = tile.colorHex
            copy.linkedBoardID = tile.linkedBoardID
            copy.isHidden = tile.isHidden
            copy.symbol = tile.symbol
            copy.imageData = tile.imageData
            copy.audioData = tile.audioData
            copy.board = board
            board.updatedAt = .now
        }
        return copy
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
    ///
    /// A folder's board is named after its tile. If the parent renames the tile and the board still has
    /// the tile's old name, the board is renamed with it, so the folder title the child sees matches.
    /// `newFolderName` also makes a new folder board for the tile, in the same undo step.
    func update(_ tile: Tile, newFolderName: String? = nil, rows: Int = 3, columns: Int = 3, _ edit: (Tile) -> Void) {
        change("Edit Tile") {
            let oldLabel = tile.label
            edit(tile)
            if let newFolderName {
                let board = Board(name: newFolderName, rows: rows, columns: columns, isHome: false)
                context.insert(board)
                tile.linkedBoardID = board.id
            } else if let id = tile.linkedBoardID, oldLabel != tile.label, let folder = board(id),
                      folder.name.localizedCaseInsensitiveCompare(oldLabel) == .orderedSame, !tile.label.isEmpty {
                folder.name = Self.folderName(from: tile.label)
                folder.updatedAt = .now
            }
            tile.updatedAt = .now
            tile.board?.updatedAt = .now
        }
    }

    /// Adds a new tile from the tile editor, and its folder board if asked. One undo step.
    @discardableResult
    func addTile(to board: Board, row: Int, column: Int, phoneSpot: PhoneLayout.Spot? = nil, newFolderName: String? = nil,
                 rows: Int = 3, columns: Int = 3, _ edit: (Tile) -> Void) -> Tile {
        let tile = Tile(label: "", spokenText: "", row: row, column: column)
        change(newFolderName == nil ? "Add Tile" : "New Folder") {
            context.insert(tile)
            tile.board = board
            // Added on a phone: it goes where the parent tapped there, too.
            tile.phonePage = phoneSpot?.page
            tile.phoneRow = phoneSpot?.row
            tile.phoneColumn = phoneSpot?.column
            edit(tile)
            if let newFolderName {
                let folder = Board(name: newFolderName, rows: rows, columns: columns, isHome: false)
                context.insert(folder)
                tile.linkedBoardID = folder.id
            }
            board.updatedAt = .now
        }
        return tile
    }

    /// Makes a folder and a tile on `host` that opens it, in the first empty spot (or the "needs a spot"
    /// tray when `host` is full). One undo step.
    @discardableResult
    func addFolder(named name: String, on host: Board, rows: Int, columns: Int) -> Board {
        let spot = firstEmptySpot(on: host)
        let folder = Board(name: name, rows: rows, columns: columns, isHome: false)
        change("New Folder") {
            context.insert(folder)
            let tile = Tile(label: name, spokenText: "", row: spot?.row, column: spot?.column)
            context.insert(tile)
            tile.board = host
            tile.linkedBoardID = folder.id
            tile.symbol = EmojiSuggester.suggestion(label: name, spokenText: "") ?? "📁"
            host.updatedAt = .now
        }
        return folder
    }

    /// "snack" → "Snack": a folder title from a tile label.
    static func folderName(from label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "New folder" }
        return first.uppercased() + trimmed.dropFirst()
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
