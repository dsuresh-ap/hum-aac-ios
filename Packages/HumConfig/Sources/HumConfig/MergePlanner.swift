// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Plans what an import will do *before* anything changes, so the parent can see a preview.
///
/// This is where the motor-plan rule is enforced for imports, AI proposals and App Intents:
/// - **Merge** (default): add new boards and tiles, update matching IDs, and never move or delete
///   anything. A new tile whose spot is taken becomes *unplaced*; it never pushes another tile.
/// - **Replace everything**: the incoming file becomes the setup. The app makes a backup first.
public enum MergePlanner {
    public enum Mode: Sendable { case merge, replace }

    /// A new tile that could not go where the file asked, because the spot was taken or outside the grid.
    /// The parent places it by hand in edit mode.
    public struct UnplacedTile: Equatable, Sendable {
        public var boardID: UUID
        public var tile: HumTile
    }

    public struct Summary: Equatable, Sendable {
        public var newBoards = 0
        public var newTiles = 0
        public var changedTiles = 0
        public var removedTiles = 0
        public var movedTiles = 0
        public var unplacedTiles = 0
        /// Set when the file's own Home became a folder on your Home (a merge into a setup that has one).
        public var homeFolderName: String?

        /// Plain-language sentence for the preview, e.g. "3 new tiles, 2 changed tiles, 0 removed. No tiles will move."
        public var sentence: String {
            var parts: [String] = []
            if newBoards > 0 { parts.append(plural(newBoards, "new board")) }
            parts.append(plural(newTiles, "new tile"))
            parts.append(plural(changedTiles, "changed tile"))
            parts.append("\(removedTiles) removed")
            var text = parts.joined(separator: ", ") + "."
            text += movedTiles == 0 ? " No tiles will move." : " \(plural(movedTiles, "tile")) will move."
            if let homeFolderName {
                text += " The file's Home becomes a folder called “\(homeFolderName)” on your Home."
            }
            if unplacedTiles > 0 {
                text += " \(plural(unplacedTiles, "new tile")) will need a spot. You can place \(unplacedTiles == 1 ? "it" : "them") in edit mode."
            }
            return text
        }

        private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
    }

    public struct Plan: Equatable, Sendable {
        public var mode: Mode
        /// The setup after the import (placed tiles only).
        public var result: HumDocument
        public var unplaced: [UnplacedTile]
        public var summary: Summary
        /// IDs of tiles whose content changed (for highlighting in the preview).
        public var changedTileIDs: Set<UUID>
        public var newTileIDs: Set<UUID>
    }

    /// `name` names the folder that opens the file's Home in a merge (usually the file name).
    public static func plan(existing: HumDocument, incoming: HumDocument, mode: Mode, name: String? = nil) -> Plan {
        switch mode {
        case .replace: return planReplace(existing: existing, incoming: incoming)
        case .merge: return planMerge(existing: existing, incoming: incoming, name: name)
        }
    }

    /// The folder name for a file's Home: the given name, else the document's, else "Imported".
    static func folderName(_ name: String?, _ incoming: HumDocument) -> String {
        for candidate in [name, incoming.name] {
            let trimmed = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.localizedCaseInsensitiveCompare("Home") != .orderedSame { return trimmed }
        }
        return "Imported"
    }

    // MARK: - Merge

    private static func planMerge(existing: HumDocument, incoming: HumDocument, name: String?) -> Plan {
        var result = existing
        var summary = Summary()
        var unplaced: [UnplacedTile] = []
        var changed: Set<UUID> = []
        var added: Set<UUID> = []

        // Where every existing tile lives: tile ID → (board index, tile index).
        var tileIndex: [UUID: (Int, Int)] = [:]
        for (b, board) in result.boards.enumerated() {
            for (t, tile) in board.tiles.enumerated() { tileIndex[tile.id] = (b, t) }
        }
        let hasHome = result.boards.contains(where: \.isHome)
        var importedHome: HumBoard?

        for incomingBoard in incoming.boards {
            let boardPosition: Int
            if let existingIndex = result.boards.firstIndex(where: { $0.id == incomingBoard.id }) {
                boardPosition = existingIndex
                // Rename is fine. The grid can only grow in a merge (growing never moves tiles).
                result.boards[existingIndex].name = incomingBoard.name
                result.boards[existingIndex].rows = max(result.boards[existingIndex].rows, incomingBoard.rows)
                result.boards[existingIndex].columns = max(result.boards[existingIndex].columns, incomingBoard.columns)
                result.boards[existingIndex].extra.merge(incomingBoard.extra) { _, new in new }
            } else {
                var newBoard = incomingBoard
                newBoard.tiles = []
                // Never take Home away from the existing setup in a merge. The file's Home becomes a
                // folder instead, named after the file, so there aren't two boards called "Home".
                if hasHome && newBoard.isHome {
                    newBoard.isHome = false
                    newBoard.name = folderName(name, incoming)
                    importedHome = newBoard
                }
                result.boards.append(newBoard)
                boardPosition = result.boards.count - 1
                summary.newBoards += 1
            }

            for incomingTile in incomingBoard.tiles {
                if let (b, t) = tileIndex[incomingTile.id] {
                    // Existing tile: update what it says and looks like, keep where it is.
                    let before = result.boards[b].tiles[t]
                    var updated = before
                    updated.label = incomingTile.label
                    updated.spokenText = incomingTile.spokenText
                    updated.function = incomingTile.function
                    updated.color = incomingTile.color
                    updated.linkedBoardID = incomingTile.linkedBoardID
                    updated.hidden = incomingTile.hidden
                    updated.symbol = incomingTile.symbol
                    // Media is only ever added or replaced in a merge, never removed by a file that lacks it.
                    if incomingTile.image != nil { updated.image = incomingTile.image }
                    if incomingTile.audio != nil { updated.audio = incomingTile.audio }
                    updated.extra.merge(incomingTile.extra) { _, new in new }
                    if updated != before {
                        result.boards[b].tiles[t] = updated
                        changed.insert(updated.id)
                    }
                } else {
                    // New tile: use the requested spot only if it is inside the grid and free.
                    let board = result.boards[boardPosition]
                    let inGrid = (0..<board.rows).contains(incomingTile.row) && (0..<board.columns).contains(incomingTile.column)
                    if inGrid && board.tile(atRow: incomingTile.row, column: incomingTile.column) == nil {
                        result.boards[boardPosition].tiles.append(incomingTile)
                        tileIndex[incomingTile.id] = (boardPosition, result.boards[boardPosition].tiles.count - 1)
                    } else {
                        unplaced.append(UnplacedTile(boardID: board.id, tile: incomingTile))
                    }
                    added.insert(incomingTile.id)
                }
            }
        }

        // A tile on your Home that opens the file's Home (like TD Snap's "import and link"), so the child
        // can reach everything that came in. First empty spot, else the "needs a spot" tray.
        if let importedHome, let homeIndex = result.boards.firstIndex(where: \.isHome) {
            let home = result.boards[homeIndex]
            var spot: (Int, Int)?
            search: for r in 0..<home.rows {
                for c in 0..<home.columns where home.tile(atRow: r, column: c) == nil {
                    spot = (r, c)
                    break search
                }
            }
            let folderTile = HumTile(label: importedHome.name, spokenText: "", row: spot?.0 ?? 0, column: spot?.1 ?? 0,
                                     linkedBoardID: importedHome.id,
                                     symbol: EmojiSuggester.suggestion(label: importedHome.name, spokenText: "") ?? "📁")
            if spot != nil {
                result.boards[homeIndex].tiles.append(folderTile)
            } else {
                unplaced.append(UnplacedTile(boardID: home.id, tile: folderTile))
            }
            added.insert(folderTile.id)
            summary.homeFolderName = importedHome.name
        }

        summary.newTiles = added.count
        summary.changedTiles = changed.count
        summary.unplacedTiles = unplaced.count
        if result.settings == nil { result.settings = incoming.settings }
        return Plan(mode: .merge, result: result, unplaced: unplaced, summary: summary, changedTileIDs: changed, newTileIDs: added)
    }

    // MARK: - Replace

    private static func planReplace(existing: HumDocument, incoming: HumDocument) -> Plan {
        var summary = Summary()
        var changed: Set<UUID> = []
        var added: Set<UUID> = []
        var old: [UUID: HumTile] = [:]
        for board in existing.boards { for tile in board.tiles { old[tile.id] = tile } }
        var oldBoardOf: [UUID: UUID] = [:]
        for board in existing.boards { for tile in board.tiles { oldBoardOf[tile.id] = board.id } }

        var seen: Set<UUID> = []
        for board in incoming.boards {
            if !existing.boards.contains(where: { $0.id == board.id }) { summary.newBoards += 1 }
            for tile in board.tiles {
                seen.insert(tile.id)
                guard let before = old[tile.id] else { added.insert(tile.id); continue }
                if before.row != tile.row || before.column != tile.column || oldBoardOf[tile.id] != board.id {
                    summary.movedTiles += 1
                }
                var a = before, b = tile
                (a.row, a.column, b.row, b.column) = (0, 0, 0, 0)
                if a != b { changed.insert(tile.id) }
            }
        }
        summary.newTiles = added.count
        summary.changedTiles = changed.count
        summary.removedTiles = old.keys.filter { !seen.contains($0) }.count
        return Plan(mode: .replace, result: incoming, unplaced: [], summary: summary, changedTileIDs: changed, newTileIDs: added)
    }
}
