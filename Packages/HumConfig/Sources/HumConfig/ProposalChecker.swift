// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A tile suggested by the AI helper, before any checks.
public struct ProposedTile: Sendable, Equatable {
    public var label: String
    public var spokenText: String
    public var function: TileFunction?
    /// A sub-board name the model suggests (nil = the board the parent is editing).
    public var boardName: String?

    public init(label: String, spokenText: String, function: TileFunction? = nil, boardName: String? = nil) {
        self.label = label
        self.spokenText = spokenText
        self.function = function
        self.boardName = boardName
    }
}

public struct ProposalCheckResult: Sendable, Equatable {
    public var tiles: [ProposedTile]
    /// Plain-language notes for the parent about what the checks changed.
    public var notes: [String]
}

/// Code-level GLP rules for AI output. The model is told these rules too, but **code checks win**:
/// whatever the model returns passes through here, then the normal import preview, then the parent's Apply.
public enum ProposalChecker {
    public static let maxLabelWords = 4

    public static func check(_ proposal: [ProposedTile], parentPhrases: [String], existing: HumDocument) -> ProposalCheckResult {
        var notes: [String] = []
        var tiles: [ProposedTile] = []
        let phrases = parentPhrases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        for var tile in proposal {
            tile.spokenText = String(tile.spokenText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            tile.label = String(tile.label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            if tile.spokenText.isEmpty { continue }

            // 1. No praise, reward or compliance phrases.
            if let bad = GLPRules.discouragedPhrase(in: tile.spokenText) ?? GLPRules.discouragedPhrase(in: tile.label) {
                notes.append("Left out “\(tile.spokenText)” because “\(bad)” is praise or an instruction, not the child's voice.")
                continue
            }
            // 2. A fragment of a parent's gestalt becomes the whole gestalt again.
            if let whole = phrases.first(where: { GLPRules.isFragment(tile.spokenText, of: $0) }) {
                notes.append("Kept “\(whole)” whole instead of splitting it.")
                tile.spokenText = whole
            }
            // 3. Short labels.
            if tile.label.isEmpty || tile.label.split(separator: " ").count > maxLabelWords {
                tile.label = shortLabel(for: tile.spokenText)
            }
            tiles.append(tile)
        }

        // 4. No duplicates, within the proposal or with tiles that already exist.
        var seen = Set(existing.boards.flatMap { $0.tiles.map { GLPRules.normalize($0.spokenText) } })
        var unique: [ProposedTile] = []
        for tile in tiles {
            let key = GLPRules.normalize(tile.spokenText)
            if seen.insert(key).inserted {
                unique.append(tile)
            } else if !tiles.isEmpty {
                // Silent for repaired splits (they collapse into one), noted for real duplicates of existing tiles.
                if existing.boards.contains(where: { $0.tiles.contains { GLPRules.normalize($0.spokenText) == key } }) {
                    notes.append("“\(tile.spokenText)” is already on your boards.")
                }
            }
        }

        // 5. Protest and regulation tiles are never only on a sub-board: also offer them on Home.
        let homeName = existing.homeBoard?.name
        let homePhrases = Set(existing.homeBoard?.tiles.map { GLPRules.normalize($0.spokenText) } ?? [])
        var extras: [ProposedTile] = []
        for tile in unique {
            guard let f = tile.function, GLPRules.mustStayOnHome.contains(f),
                  let board = tile.boardName, board != homeName,
                  !homePhrases.contains(GLPRules.normalize(tile.spokenText)) else { continue }
            var copy = tile
            copy.boardName = homeName
            extras.append(copy)
            notes.append("Also added “\(tile.label)” to Home, so it can always be reached.")
        }
        return ProposalCheckResult(tiles: unique + extras, notes: notes)
    }

    /// Builds a document holding only the new tiles, placed in free spots, for the normal import preview.
    /// Tiles for a board that doesn't exist yet go on a new board. Existing tiles are never included,
    /// so nothing can move or be removed.
    public static func document(from tiles: [ProposedTile], targetBoardID: UUID?, existing: HumDocument) -> HumDocument {
        var boards: [UUID: HumBoard] = [:]
        var order: [UUID] = []
        var occupied: [UUID: Set<String>] = [:]
        var overflow: [UUID: Int] = [:]
        for board in existing.boards {
            occupied[board.id] = Set(board.tiles.map { "\($0.row),\($0.column)" })
        }
        let fallback = existing.boards.first { $0.id == targetBoardID } ?? existing.homeBoard ?? existing.boards.first

        func boardFor(_ tile: ProposedTile) -> HumBoard {
            if let name = tile.boardName,
               let match = existing.boards.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                return boards[match.id] ?? HumBoard(id: match.id, name: match.name, rows: match.rows, columns: match.columns, isHome: match.isHome)
            }
            if let name = tile.boardName, !name.isEmpty, name != fallback?.name {
                if let made = boards.values.first(where: { $0.name == name }) { return made }
                return HumBoard(name: name, rows: 3, columns: 4)
            }
            if let fallback {
                return boards[fallback.id] ?? HumBoard(id: fallback.id, name: fallback.name, rows: fallback.rows, columns: fallback.columns, isHome: fallback.isHome)
            }
            return boards.values.first { $0.isHome } ?? HumBoard(name: "Home", rows: 3, columns: 4, isHome: true)
        }

        for proposed in tiles {
            var board = boardFor(proposed)
            if boards[board.id] == nil { order.append(board.id) }
            var taken = occupied[board.id] ?? []
            var spot: (Int, Int)?
            search: for r in 0..<board.rows {
                for c in 0..<board.columns where !taken.contains("\(r),\(c)") {
                    spot = (r, c)
                    break search
                }
            }
            // Full board: point at a distinct taken spot. The merge planner then puts the tile in the
            // "needs a spot" tray, and the document itself stays valid (no two new tiles share a spot).
            let overflowIndex = overflow[board.id, default: 0]
            let (row, column) = spot ?? ((overflowIndex / board.columns) % board.rows, overflowIndex % board.columns)
            if spot != nil { taken.insert("\(row),\(column)") } else { overflow[board.id] = overflowIndex + 1 }
            occupied[board.id] = taken
            board.tiles.append(HumTile(label: proposed.label, spokenText: proposed.spokenText, row: row, column: column, function: proposed.function))
            boards[board.id] = board
        }
        return HumDocument(boards: order.compactMap { boards[$0] })
    }

    /// First few words, without trailing punctuation.
    public static func shortLabel(for phrase: String) -> String {
        let words = phrase.split(separator: " ").prefix(maxLabelWords).joined(separator: " ")
        return words.trimmingCharacters(in: CharacterSet(charactersIn: "!?.,;: "))
    }
}
