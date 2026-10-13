// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData
import HumConfig

/// Every parent edit goes through here. It enforces the motor-plan rules and makes every change undoable.
///
/// - Only `move` and a parent's tile size change (`setColumns`) change a tile's position, and both
///   stamp `positionUpdatedAt`.
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

    /// Runs `body` as one undo step, with `undo` as the way back instead of SwiftData's own record.
    /// SwiftData can't undo a delete properly: the object comes back without its board, so the tile is
    /// lost (BUGS.md, HUM-002). `undo` runs as a change of its own, so whatever it registers is the redo.
    ///
    /// Undo makes *new* objects with the old IDs. SwiftData's older undo steps still point at the deleted
    /// ones and would crash, so a change like this (not an undo or redo of one) forgets the older steps.
    func change(_ name: String, undo: @escaping @MainActor (BoardStore) -> Void, _ body: () throws -> Void) rethrows {
        guard let undoManager else {
            try body()
            try? context.save()
            return
        }
        if !undoManager.isUndoing && !undoManager.isRedoing { undoManager.removeAllActions() }
        undoManager.beginUndoGrouping()
        undoManager.disableUndoRegistration()
        defer {
            try? context.save()  // while registration is off, so SwiftData records nothing
            undoManager.enableUndoRegistration()
            undoManager.registerUndo(withTarget: self) { store in MainActor.assumeIsolated { undo(store) } }
            undoManager.setActionName(name)
            undoManager.endUndoGrouping()
        }
        try body()
    }

    /// Runs `body` as one undo step whose Undo puts these tiles and boards back as they were and deletes
    /// whatever `body` made. Before iOS 27, SwiftData's own undo loses a tile's board when the change
    /// touched the board link, so the tile vanishes or the app crashes (BUGS.md, HUM-052).
    /// `redo` does the change again. Pictures and recordings are kept only for `mediaOf` (they can be big).
    /// Like any `change(_:undo:_:)`, it forgets older undo steps: SwiftData's own records of them don't
    /// survive this one on iOS 26 and earlier (a redo took an untouched tile off its board).
    func change(_ name: String, restoring tileIDs: Set<UUID>, boards boardIDs: Set<UUID>, mediaOf: Set<UUID> = [],
                redo: @escaping @MainActor (BoardStore) -> Void, _ body: () throws -> Void) rethrows {
        let before = Snapshot(tiles: allTiles().filter { tileIDs.contains($0.id) }.map { TileState($0, keepMedia: mediaOf.contains($0.id)) },
                              boards: boards().filter { boardIDs.contains($0.id) }.map(BoardState.init))
        let (tilesBefore, boardsBefore) = (Set(allTiles().map(\.id)), Set(boards().map(\.id)))
        // Only what `body` makes is deleted by Undo, not tiles that sync brings in later.
        let made = MadeIDs()
        try change(name, undo: { store in
            store.change(name, undo: redo) { store.restore(before, deleting: made) }
        }) {
            try body()
            made.tiles = Set(allTiles().map(\.id)).subtracting(tilesBefore)
            made.boards = Set(boards().map(\.id)).subtracting(boardsBefore)
        }
    }

    private func allTiles() -> [Tile] { (try? context.fetch(FetchDescriptor<Tile>())) ?? [] }

    private func restore(_ snapshot: Snapshot, deleting made: MadeIDs) {
        let boardsByID = Dictionary(boards().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tiles = allTiles()
        let tilesByID = Dictionary(tiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Put things back first, so nothing that existed before is on a board that's about to go.
        for state in snapshot.boards { if let board = boardsByID[state.id] { state.apply(to: board) } }
        for state in snapshot.tiles { if let tile = tilesByID[state.id] { state.apply(to: tile, boards: boardsByID) } }
        for tile in tiles where made.tiles.contains(tile.id) { context.delete(tile) }
        for board in boardsByID.values where made.boards.contains(board.id) { context.delete(board) }
    }

    /// Saves changes that aren't an undo step of their own (converted pictures, phone spots), without
    /// leaving anything on the undo stack. Undo after an import must undo the import, not these.
    func withoutUndo(_ body: () -> Void) {
        undoManager?.disableUndoRegistration()
        body()
        try? context.save()
        undoManager?.enableUndoRegistration()
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

    func tile(_ id: UUID) -> Tile? {
        var descriptor = FetchDescriptor<Tile>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func tile(on board: Board, row: Int, column: Int) -> Tile? {
        board.placedTiles.first { $0.row == row && $0.column == column }
    }

    // MARK: Tiles

    /// The rows the editor shows: the board's own rows plus one spare row, so there's always room to add
    /// a tile. A tile put in the spare row makes the board one row taller (`growRows`).
    static func editorRows(_ board: Board) -> Int { min(board.rows + 1, HumValidator.rowRange.upperBound) }

    /// Makes `board` tall enough for a tile in `row`. Call inside the change that places the tile.
    private func growRows(_ board: Board, toFit row: Int) {
        if row >= board.rows { board.rows = min(row + 1, HumValidator.rowRange.upperBound) }
    }

    /// Adds a tile to an empty slot. Throws if the slot is taken (callers only offer empty slots).
    @discardableResult
    func addTile(to board: Board, row: Int, column: Int, label: String, spokenText: String) throws -> Tile {
        guard tile(on: board, row: row, column: column) == nil else { throw StoreError.slotTaken }
        let tile = Tile(label: label, spokenText: spokenText, row: row, column: column)
        change("Add Tile") {
            context.insert(tile)
            tile.board = board
            growRows(board, toFit: row)
            board.updatedAt = .now
        }
        return tile
    }

    /// Moves a tile to a slot. If another tile is there, the two swap. Both moves are explicit parent actions.
    func move(_ tile: Tile, to row: Int, column: Int, on board: Board) {
        guard row >= 0, column >= 0, row < Self.editorRows(board), column < board.columns else { return }
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
            growRows(board, toFit: row)
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
        let (tileID, targetID) = (tile.id, target.id)
        let boardIDs = Set([tile.board?.id, target.id].compactMap { $0 })
        change("Move to Folder", restoring: [tileID], boards: boardIDs, redo: { store in
            guard let tile = store.tile(tileID), let target = store.board(targetID) else { return }
            store.moveToBoard(tile, target)
        }) {
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
            copy.imageCredit = tile.imageCredit
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

    /// Deletes a tile. Its slot simply becomes empty; nothing else moves. Undo puts it back, with the
    /// same ID, spot, picture and recording.
    func delete(_ tile: Tile) {
        let saved = SavedTile(tile)
        change("Delete Tile", undo: { $0.restore(saved) }) { context.delete(tile) }
    }

    private func restore(_ saved: SavedTile) {
        guard let boardID = saved.boardID, let board = board(boardID) else { return }
        let tile = saved.make()
        change("Delete Tile", undo: { store in
            if let tile = store.liveTile(saved.id) { store.delete(tile) }
        }) {
            context.insert(tile)
            tile.board = board
            board.updatedAt = .now
        }
    }

    func liveTile(_ id: UUID) -> Tile? {
        var descriptor = FetchDescriptor<Tile>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
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
            growRows(board, toFit: row)
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

    /// Renames a board. Folder tiles that open it and still show its old name get the new name too,
    /// so the child sees the same word on the tile and at the top of the folder.
    func rename(_ board: Board, to name: String) {
        change("Rename Board") {
            let oldName = board.name
            board.name = name
            board.updatedAt = .now
            let id = board.id
            for tile in (try? context.fetch(FetchDescriptor<Tile>())) ?? []
            where tile.linkedBoardID == id && tile.label.localizedCaseInsensitiveCompare(oldName) == .orderedSame {
                tile.label = name
                tile.updatedAt = .now
            }
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
                tile.imageCredit = source.imageCredit
                tile.audioData = source.audioData
                tile.board = copy
            }
        }
        return copy
    }

    /// Deletes a board and its tiles. Tiles elsewhere that opened it keep speaking; their link is cleared.
    func delete(_ board: Board) throws {
        if board.isHome && boards().count > 1 { throw StoreError.cannotDeleteHome }
        let saved = SavedBoard(board)
        let id = board.id
        let links = ((try? context.fetch(FetchDescriptor<Tile>())) ?? []).filter { $0.linkedBoardID == id }.map(\.id)
        change("Delete Board", undo: { $0.restore(saved, links: links) }) {
            for tile in (try? context.fetch(FetchDescriptor<Tile>())) ?? [] where tile.linkedBoardID == id {
                tile.linkedBoardID = nil
            }
            context.delete(board)
        }
    }

    private func restore(_ saved: SavedBoard, links: [UUID]) {
        change("Delete Board", undo: { store in
            if let board = store.board(saved.id) { try? store.delete(board) }
        }) {
            let board = Board(id: saved.id, name: saved.name, rows: saved.rows, columns: saved.columns, isHome: saved.isHome)
            board.createdAt = saved.createdAt
            board.extraJSON = saved.extraJSON
            context.insert(board)
            for savedTile in saved.tiles {
                let tile = savedTile.make()
                context.insert(tile)
                tile.board = board
            }
            for id in links { liveTile(id)?.linkedBoardID = saved.id }
        }
    }

    /// Tiles that would fall outside a smaller grid. Empty means the resize is safe.
    func tilesCutOff(_ board: Board, rows: Int, columns: Int) -> [Tile] {
        board.placedTiles.filter { ($0.row ?? 0) >= rows || ($0.column ?? 0) >= columns }
    }

    /// Changes the grid size without moving any tile (first run, fixtures). It's refused if tiles would be
    /// cut off; a parent's change goes through `setColumns` instead, which never cuts tiles off.
    func resize(_ board: Board, rows: Int, columns: Int) throws {
        let rows = min(max(rows, 1), HumValidator.rowRange.upperBound)
        let columns = min(max(columns, 1), HumValidator.columnRange.upperBound)
        guard rows * columns >= 2 else { throw StoreError.tooSmall }
        let cut = tilesCutOff(board, rows: rows, columns: columns)
        guard cut.isEmpty else { throw StoreError.wouldCutOff(cut.map(\.label)) }
        change("Change Grid Size") {
            board.rows = rows
            board.columns = columns
            board.updatedAt = .now
        }
    }

    /// Where every placed tile goes when `board` becomes `columns` wide, keeping reading order: left to
    /// right, top to bottom, with empty spots kept as gaps, and the rows that needs.
    ///
    /// If keeping the gaps would need more than the maximum rows, the tiles close up instead (same order).
    func reflowedSpots(_ board: Board, columns: Int) -> (spots: [UUID: (row: Int, column: Int)], rows: Int) {
        let tiles = board.placedTiles.sorted { ($0.row!, $0.column!) < ($1.row!, $1.column!) }
        guard columns != board.columns else {
            let spots = Dictionary(uniqueKeysWithValues: tiles.map { ($0.id, (row: $0.row!, column: $0.column!)) })
            return (spots, (tiles.map { $0.row! }.max() ?? -1) + 1)
        }
        var indices = tiles.map { $0.row! * board.columns + $0.column! }
        if let last = indices.last, last / columns >= HumValidator.rowRange.upperBound {
            indices = Array(indices.indices)
        }
        var spots: [UUID: (row: Int, column: Int)] = [:]
        for (tile, index) in zip(tiles, indices) { spots[tile.id] = (index / columns, index % columns) }
        return (spots, indices.last.map { $0 / columns + 1 } ?? 0)
    }

    /// The fewest columns that still fit every placed tile within the maximum rows.
    func minimumColumns(_ board: Board) -> Int {
        let count = board.placedTiles.count
        let maxRows = HumValidator.rowRange.upperBound
        return max(1, (count + maxRows - 1) / maxRows)
    }

    /// Changes how many tiles go across, from the parent's tile size slider. One undo step.
    ///
    /// Tiles re-flow in reading order (`reflowedSpots`): the order the child knows stays the same, and the
    /// board gets exactly the rows its tiles need. Nothing is cut off and nothing goes to the tray.
    func setColumns(_ board: Board, _ columns: Int) {
        let columns = min(max(columns, minimumColumns(board)), HumValidator.columnRange.upperBound)
        let (spots, needed) = reflowedSpots(board, columns: columns)
        // At least 2 spots, and at least one row.
        let rows = min(max(needed, columns == 1 ? 2 : 1), HumValidator.rowRange.upperBound)
        change("Change Tile Size") {
            let now = Date.now
            for tile in board.placedTiles {
                guard let spot = spots[tile.id], spot.row != tile.row || spot.column != tile.column else { continue }
                tile.row = spot.row
                tile.column = spot.column
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

/// Everything about a deleted tile, so Undo can make it again.
struct SavedTile {
    var id: UUID
    var boardID: UUID?
    var label, spokenText: String
    var functionRaw, colorHex, symbol: String?
    var linkedBoardID: UUID?
    var isHidden: Bool
    var row, column, phonePage, phoneRow, phoneColumn: Int?
    var positionUpdatedAt, createdAt: Date
    var imageData, audioData, extraJSON: Data?
    var imageCredit: String?

    @MainActor
    init(_ tile: Tile) {
        id = tile.id
        boardID = tile.board?.id
        label = tile.label
        spokenText = tile.spokenText
        functionRaw = tile.functionRaw
        colorHex = tile.colorHex
        symbol = tile.symbol
        linkedBoardID = tile.linkedBoardID
        isHidden = tile.isHidden
        row = tile.row
        column = tile.column
        phonePage = tile.phonePage
        phoneRow = tile.phoneRow
        phoneColumn = tile.phoneColumn
        positionUpdatedAt = tile.positionUpdatedAt
        createdAt = tile.createdAt
        imageData = tile.imageData
        imageCredit = tile.imageCredit
        audioData = tile.audioData
        extraJSON = tile.extraJSON
    }

    @MainActor
    func make() -> Tile {
        let tile = Tile(id: id, label: label, spokenText: spokenText, row: row, column: column)
        tile.functionRaw = functionRaw
        tile.colorHex = colorHex
        tile.symbol = symbol
        tile.linkedBoardID = linkedBoardID
        tile.isHidden = isHidden
        tile.phonePage = phonePage
        tile.phoneRow = phoneRow
        tile.phoneColumn = phoneColumn
        tile.positionUpdatedAt = positionUpdatedAt
        tile.createdAt = createdAt
        tile.imageData = imageData
        tile.imageCredit = imageCredit
        tile.audioData = audioData
        tile.extraJSON = extraJSON
        return tile
    }
}

/// Everything about a deleted board and its tiles.
struct SavedBoard {
    var id: UUID
    var name: String
    var rows, columns: Int
    var isHome: Bool
    var createdAt: Date
    var extraJSON: Data?
    var tiles: [SavedTile]

    @MainActor
    init(_ board: Board) {
        id = board.id
        name = board.name
        rows = board.rows
        columns = board.columns
        isHome = board.isHome
        createdAt = board.createdAt
        extraJSON = board.extraJSON
        tiles = (board.tiles ?? []).map(SavedTile.init)
    }
}

/// Tiles and boards as they were before a change, for `BoardStore.change(_:restoring:boards:mediaOf:redo:_:)`.
private struct Snapshot {
    let tiles: [TileState]
    let boards: [BoardState]
}

/// What a change made, filled in once it has run. Undo deletes these.
private final class MadeIDs {
    var tiles: Set<UUID> = []
    var boards: Set<UUID> = []
}

private struct TileState {
    let id: UUID, boardID: UUID?
    let label: String, spokenText: String, functionRaw: String?, colorHex: String?
    let linkedBoardID: UUID?, isHidden: Bool, symbol: String?, extraJSON: Data?
    let row: Int?, column: Int?, positionUpdatedAt: Date
    let phonePage: Int?, phoneRow: Int?, phoneColumn: Int?
    let updatedAt: Date
    let media: (image: Data?, credit: String?, audio: Data?)?

    init(_ tile: Tile, keepMedia: Bool) {
        id = tile.id; boardID = tile.board?.id
        label = tile.label; spokenText = tile.spokenText; functionRaw = tile.functionRaw; colorHex = tile.colorHex
        linkedBoardID = tile.linkedBoardID; isHidden = tile.isHidden; symbol = tile.symbol; extraJSON = tile.extraJSON
        row = tile.row; column = tile.column; positionUpdatedAt = tile.positionUpdatedAt
        phonePage = tile.phonePage; phoneRow = tile.phoneRow; phoneColumn = tile.phoneColumn
        updatedAt = tile.updatedAt
        media = keepMedia ? (tile.imageData, tile.imageCredit, tile.audioData) : nil
    }

    func apply(to tile: Tile, boards: [UUID: Board]) {
        if tile.board?.id != boardID { tile.board = boardID.flatMap { boards[$0] } }
        tile.label = label; tile.spokenText = spokenText; tile.functionRaw = functionRaw; tile.colorHex = colorHex
        tile.linkedBoardID = linkedBoardID; tile.isHidden = isHidden; tile.symbol = symbol; tile.extraJSON = extraJSON
        tile.row = row; tile.column = column; tile.positionUpdatedAt = positionUpdatedAt
        tile.phonePage = phonePage; tile.phoneRow = phoneRow; tile.phoneColumn = phoneColumn
        tile.updatedAt = updatedAt
        if let media { tile.imageData = media.image; tile.imageCredit = media.credit; tile.audioData = media.audio }
    }
}

private struct BoardState {
    let id: UUID, name: String, rows: Int, columns: Int, isHome: Bool, extraJSON: Data?, updatedAt: Date

    init(_ board: Board) {
        id = board.id; name = board.name; rows = board.rows; columns = board.columns
        isHome = board.isHome; extraJSON = board.extraJSON; updatedAt = board.updatedAt
    }

    func apply(to board: Board) {
        board.name = name; board.rows = rows; board.columns = columns
        board.isHome = isHome; board.extraJSON = extraJSON; board.updatedAt = updatedAt
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
