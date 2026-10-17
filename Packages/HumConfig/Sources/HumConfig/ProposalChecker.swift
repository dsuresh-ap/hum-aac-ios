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
    /// Placeholder emoji until the parent adds a photo. Filled in from the words when nil.
    public var symbol: String?

    public init(label: String, spokenText: String, function: TileFunction? = nil, boardName: String? = nil, symbol: String? = nil) {
        self.label = label
        self.spokenText = spokenText
        self.function = function
        self.boardName = boardName
        self.symbol = symbol
    }
}

public struct ProposalCheckResult: Sendable, Equatable {
    public var tiles: [ProposedTile]
    /// Notes for the parent about what the checks changed.
    public var notes: [ProposalNote]
}

/// What the checks changed, for the parent. The app shows these in its own language; `text` is the
/// English version (for the command-line tool and tests).
public enum ProposalNote: Sendable, Hashable {
    /// A tile was left out because `word` is praise or an instruction.
    case leftOutPraise(phrase: String, word: String)
    /// A fragment of a parent's phrase was put back together.
    case keptWhole(phrase: String)
    /// The phrase is already on the boards.
    case alreadyOnBoards(phrase: String)

    public var text: String {
        switch self {
        case .leftOutPraise(let phrase, let word):
            return "Left out “\(phrase)” because “\(word)” is praise or an instruction, not the child's voice."
        case .keptWhole(let phrase): return "Kept “\(phrase)” whole instead of splitting it."
        case .alreadyOnBoards(let phrase): return "“\(phrase)” is already on your boards."
        }
    }
}

/// Code-level GLP rules for AI output. The model is told these rules too, but **code checks win**:
/// whatever the model returns passes through here, then the normal import preview, then the parent's Apply.
public enum ProposalChecker {
    public static let maxLabelWords = 4

    public static func check(_ proposal: [ProposedTile], parentPhrases: [String], existing: HumDocument) -> ProposalCheckResult {
        var notes: [ProposalNote] = []
        var tiles: [ProposedTile] = []
        let phrases = parentPhrases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        for var tile in proposal {
            tile.spokenText = String(tile.spokenText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            tile.label = String(tile.label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            if tile.spokenText.isEmpty { continue }

            // 1. No praise, reward or compliance phrases.
            if let bad = GLPRules.discouragedPhrase(in: tile.spokenText) ?? GLPRules.discouragedPhrase(in: tile.label) {
                notes.append(.leftOutPraise(phrase: tile.spokenText, word: bad))
                continue
            }
            // 2. A fragment of a parent's gestalt becomes the whole gestalt again.
            if let whole = phrases.first(where: { GLPRules.isFragment(tile.spokenText, of: $0) }) {
                notes.append(.keptWhole(phrase: whole))
                tile.spokenText = whole
            }
            // 3. Short labels.
            if tile.label.isEmpty || tile.label.split(separator: " ").count > maxLabelWords {
                tile.label = shortLabel(for: tile.spokenText)
            }
            // 4. One real emoji as the placeholder picture, or a guess from the words.
            if let symbol = tile.symbol, !EmojiSuggester.isSingleEmoji(symbol) { tile.symbol = nil }
            if tile.symbol == nil { tile.symbol = EmojiSuggester.suggestion(label: tile.label, spokenText: tile.spokenText) }
            tiles.append(tile)
        }

        // 5. No duplicates, within the proposal or with tiles that already exist.
        var seen = Set(existing.boards.flatMap { $0.tiles.map { GLPRules.normalize($0.spokenText) } })
        var unique: [ProposedTile] = []
        for tile in tiles {
            let key = GLPRules.normalize(tile.spokenText)
            if seen.insert(key).inserted {
                unique.append(tile)
            } else if !tiles.isEmpty {
                // Silent for repaired splits (they collapse into one), noted for real duplicates of existing tiles.
                if existing.boards.contains(where: { $0.tiles.contains { GLPRules.normalize($0.spokenText) == key } }) {
                    notes.append(.alreadyOnBoards(phrase: tile.spokenText))
                }
            }
        }

        return ProposalCheckResult(tiles: unique, notes: notes)
    }

    /// Builds a document holding only the new tiles, placed in free spots, for the normal import preview.
    /// Tiles go on the board being edited. A tile can go elsewhere only when the model named a folder:
    /// - a folder that a tile on the board being edited already opens;
    /// - a new folder, which gets a folder tile on the board being edited, so the child can reach it.
    /// Any other board name is ignored. Existing tiles are never included, so nothing can move or be removed.
    public static func document(from tiles: [ProposedTile], targetBoardID: UUID?, existing: HumDocument) -> HumDocument {
        var boards: [UUID: HumBoard] = [:]
        var order: [UUID] = []
        var occupied: [UUID: Set<String>] = [:]
        var overflow: [UUID: Int] = [:]
        for board in existing.boards {
            occupied[board.id] = Set(board.tiles.map { "\($0.row),\($0.column)" })
        }
        let fallback = existing.boards.first { $0.id == targetBoardID } ?? existing.homeBoard ?? existing.boards.first
        let reachable = Set(fallback?.tiles.compactMap(\.linkedBoardID) ?? [])
        /// New folders by name, and the board each folder tile goes on.
        var newFolders: [String: UUID] = [:]

        func copy(of board: HumBoard) -> HumBoard {
            boards[board.id] ?? HumBoard(id: board.id, name: board.name, rows: board.rows, columns: board.columns, isHome: board.isHome)
        }

        func boardFor(_ tile: ProposedTile) -> HumBoard {
            let name = tile.boardName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sameName = { (other: String) in other.localizedCaseInsensitiveCompare(name) == .orderedSame }
            if !name.isEmpty, let fallback, !sameName(fallback.name) {
                if let match = existing.boards.first(where: { sameName($0.name) }) {
                    if reachable.contains(match.id) { return copy(of: match) }
                    return copy(of: fallback)  // a board the child can't reach from here: stay on this one
                }
                if let made = newFolders[name.lowercased()], let board = boards[made] { return board }
                let folder = HumBoard(name: name, rows: 3, columns: 4)
                newFolders[name.lowercased()] = folder.id
                return folder
            }
            if let fallback { return copy(of: fallback) }
            return boards.values.first { $0.isHome } ?? HumBoard(name: "Home", rows: 3, columns: 4, isHome: true)
        }

        func place(_ tile: HumTile, on board: inout HumBoard) {
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
            var placed = tile
            placed.row = row
            placed.column = column
            board.tiles.append(placed)
            if boards[board.id] == nil { order.append(board.id) }
            boards[board.id] = board
        }

        for proposed in tiles {
            var board = boardFor(proposed)
            let isNewFolder = newFolders.values.contains(board.id) && boards[board.id] == nil
            if isNewFolder, var host = fallback.map(copy(of:)) {
                // The tile that opens the new folder goes on the board being edited, before the folder's tiles.
                let folderTile = HumTile(label: board.name, spokenText: "", row: 0, column: 0, linkedBoardID: board.id,
                                         symbol: EmojiSuggester.suggestion(label: board.name, spokenText: "") ?? "📁")
                place(folderTile, on: &host)
            }
            place(HumTile(label: proposed.label, spokenText: proposed.spokenText, row: 0, column: 0,
                          function: proposed.function, symbol: proposed.symbol), on: &board)
        }
        return HumDocument(boards: order.compactMap { boards[$0] })
    }

    /// "Paste phrases" without AI: one line is one whole gestalt, never split. Blank lines are skipped.
    public static func tiles(fromLines text: String) -> [ProposedTile] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { ProposedTile(label: shortLabel(for: $0), spokenText: $0) }
    }

    /// Small words a label shouldn't end on ("Let's go to the" reads like a mistake).
    static let trailingWords: Set<String> = [
        "a", "an", "the", "to", "of", "and", "or", "in", "on", "at", "for", "with", "from", "my", "your", "our",
        "is", "are", "some", "this", "that",
    ]

    /// First few words, without trailing punctuation or a dangling small word:
    /// "Let's go to the park!" → "Let's go to the" → "Let's go".
    public static func shortLabel(for phrase: String) -> String {
        let punctuation = CharacterSet(charactersIn: "!?.,;:\u{201C}\u{201D}\" ")
        var words = phrase.split(separator: " ").prefix(maxLabelWords).map(String.init)
        let cut = phrase.split(separator: " ").count > words.count
        while cut, words.count > 1,
              trailingWords.contains(words.last!.lowercased().trimmingCharacters(in: punctuation)) {
            words.removeLast()
        }
        return words.joined(separator: " ").trimmingCharacters(in: punctuation)
    }
}
