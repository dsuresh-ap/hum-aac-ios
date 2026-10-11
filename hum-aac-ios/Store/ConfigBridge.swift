// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData
import HumConfig

/// Converts between SwiftData models and the open config format.
///
/// Every import path (starter board, files, AI, App Intents) goes through
/// `MergePlanner` → `ConfigBridge.apply`, so the motor-plan rules live in one place.
enum ConfigBridge {
    /// Media path used when exporting a tile's photo or recording.
    static func imagePath(for id: UUID) -> String { "media/\(id.uuidString.lowercased()).jpg" }
    static func audioPath(for id: UUID) -> String { "media/\(id.uuidString.lowercased()).m4a" }

    // MARK: Export (SwiftData → HumDocument)

    /// The whole setup as a document plus its media. Unplaced tiles have no grid spot, so they are
    /// left out of the file (the parent places them first).
    static func export(boards: [Board]) -> (document: HumDocument, media: [String: Data]) {
        var media: [String: Data] = [:]
        let humBoards = boards.sorted { ($0.isHome ? 0 : 1, $0.createdAt) < ($1.isHome ? 0 : 1, $1.createdAt) }.map { board in
            let tiles = board.placedTiles
                .sorted { ($0.row ?? 0, $0.column ?? 0) < ($1.row ?? 0, $1.column ?? 0) }
                .map { tile -> HumTile in
                    var image: String?
                    var audio: String?
                    if let data = tile.imageData {
                        image = imagePath(for: tile.id)
                        media[image!] = data
                    }
                    if let data = tile.audioData {
                        audio = audioPath(for: tile.id)
                        media[audio!] = data
                    }
                    return HumTile(
                        id: tile.id, label: tile.label, spokenText: tile.spokenText,
                        row: tile.row ?? 0, column: tile.column ?? 0, function: tile.function,
                        color: tile.colorHex, linkedBoardID: tile.linkedBoardID, hidden: tile.isHidden,
                        image: image, audio: audio, symbol: tile.symbol, extra: decodeExtra(tile.extraJSON))
                }
            return HumBoard(id: board.id, name: board.name, rows: board.rows, columns: board.columns,
                            isHome: board.isHome, tiles: tiles, extra: decodeExtra(board.extraJSON))
        }
        return (HumDocument(boards: humBoards), media)
    }

    // MARK: Apply (MergePlanner.Plan → SwiftData)

    /// One picture from a package, ready to store: resized and flattened like photos added in the app
    /// (`normalizedImportImage`). SVG that can't be drawn here yet (iOS) is kept as is and drawn right
    /// after the import. Nil if it isn't a picture.
    nonisolated static func preparedPicture(_ raw: Data) -> Data? {
        ImageProcessing.normalizedImportImage(raw) ?? (ImageProcessing.isSVG(raw) ? raw : nil)
    }

    /// The package pictures `plan` uses, by path.
    nonisolated static func picturePaths(in plan: MergePlanner.Plan, media: [String: Data]) -> [String] {
        let tiles = plan.result.boards.flatMap(\.tiles) + plan.unplaced.map(\.tile)
        return Array(Set(tiles.compactMap(\.image).filter { media[$0] != nil })).sorted()
    }

    /// Prepares every picture `plan` uses, several at a time off the main thread (a big setup can have
    /// well over a thousand). `progress` gets (done, total) on the main actor after each one.
    @MainActor
    static func preparePictures(for plan: MergePlanner.Plan, media: [String: Data],
                                progress: (Int, Int) -> Void) async -> [String: Data?] {
        let paths = picturePaths(in: plan, media: media)
        var prepared: [String: Data?] = [:]
        progress(0, paths.count)
        await withTaskGroup(of: (String, Data?).self) { group in
            var next = paths.makeIterator()
            func addNext() {
                guard let path = next.next(), let raw = media[path] else { return }
                group.addTask { (path, preparedPicture(raw)) }
            }
            for _ in 0..<max(2, ProcessInfo.processInfo.activeProcessorCount) { addNext() }
            for await (path, data) in group {
                prepared[path] = data
                progress(prepared.count, paths.count)
                addNext()
            }
        }
        return prepared
    }

    /// Writes a planned import into SwiftData. Media is only set when the package contains it.
    /// `prepared` holds pictures already processed by `preparePictures`; others are processed here.
    @MainActor
    static func apply(_ plan: MergePlanner.Plan, media: [String: Data], prepared: [String: Data?] = [:],
                      in context: ModelContext) throws {
        // Each file once, even if several tiles use it.
        var pictures = prepared
        func picture(_ path: String) -> Data? {
            if let done = pictures[path] { return done }
            guard let raw = media[path] else { return nil }
            let ready = preparedPicture(raw)
            pictures[path] = ready
            return ready
        }
        let allBoards = try context.fetch(FetchDescriptor<Board>())
        let allTiles = try context.fetch(FetchDescriptor<Tile>())
        // If sync ever produced duplicates, the first one wins; the resolver cleans up later.
        var boardsByID: [UUID: Board] = [:]
        for board in allBoards where boardsByID[board.id] == nil { boardsByID[board.id] = board }
        var tilesByID: [UUID: Tile] = [:]
        for tile in allTiles where tilesByID[tile.id] == nil { tilesByID[tile.id] = tile }
        let now = Date.now

        func upsertTile(_ humTile: HumTile, on board: Board, placed: Bool) {
            let tile = tilesByID[humTile.id] ?? {
                let t = Tile(id: humTile.id, label: humTile.label, spokenText: humTile.spokenText, row: nil, column: nil)
                context.insert(t)
                tilesByID[humTile.id] = t
                return t
            }()
            tile.label = humTile.label
            tile.spokenText = humTile.spokenText
            tile.function = humTile.function
            tile.colorHex = humTile.color
            tile.linkedBoardID = humTile.linkedBoardID
            tile.isHidden = humTile.hidden
            tile.symbol = humTile.symbol
            tile.extraJSON = encodeExtra(humTile.extra)
            // A file that isn't a readable picture never replaces the tile's current one.
            if let path = humTile.image, let data = picture(path) { tile.imageData = data }
            if let path = humTile.audio, let data = media[path] { tile.audioData = data }
            let newRow = placed ? humTile.row : nil
            let newColumn = placed ? humTile.column : nil
            if tile.row != newRow || tile.column != newColumn {
                tile.row = newRow
                tile.column = newColumn
                tile.positionUpdatedAt = now
            }
            if tile.board?.id != board.id {
                tile.board = board
                tile.phonePage = nil  // its phone spot was on the old board
                tile.phoneRow = nil
                tile.phoneColumn = nil
            }
            tile.updatedAt = now
        }

        for humBoard in plan.result.boards {
            let board = boardsByID[humBoard.id] ?? {
                let b = Board(id: humBoard.id, name: humBoard.name, rows: humBoard.rows, columns: humBoard.columns)
                context.insert(b)
                boardsByID[humBoard.id] = b
                return b
            }()
            board.name = humBoard.name
            board.rows = humBoard.rows
            board.columns = humBoard.columns
            board.isHome = humBoard.isHome
            board.extraJSON = encodeExtra(humBoard.extra)
            board.updatedAt = now
            for humTile in humBoard.tiles { upsertTile(humTile, on: board, placed: true) }
        }
        for item in plan.unplaced {
            guard let board = boardsByID[item.boardID] else { continue }
            upsertTile(item.tile, on: board, placed: false)
        }

        if plan.mode == .replace {
            let keepBoards = Set(plan.result.boards.map(\.id))
            let keepTiles = Set(plan.result.boards.flatMap { $0.tiles.map(\.id) })
            for tile in allTiles where !keepTiles.contains(tile.id) { context.delete(tile) }
            for board in allBoards where !keepBoards.contains(board.id) { context.delete(board) }
        }
        try context.save()
    }

    // MARK: Unknown-field storage

    static func encodeExtra(_ extra: [String: JSONValue]) -> Data? {
        extra.isEmpty ? nil : try? JSONEncoder().encode(extra)
    }

    static func decodeExtra(_ data: Data?) -> [String: JSONValue] {
        guard let data else { return [:] }
        return (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
    }
}
