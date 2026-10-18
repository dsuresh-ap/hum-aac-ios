// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Checks that need more than the JSON Schema: unique IDs, grid placement, links, and GLP rules.
public enum HumValidator {
    /// Supported grid sizes (inclusive). Rows go up to 20 because a tall board scrolls down.
    public static let rowRange = 1...20
    public static let columnRange = 1...8

    public static func semanticIssues(in doc: HumDocument) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var boardIDs: Set<UUID> = []
        var tileIDs: Set<UUID> = []

        let homes = doc.boards.filter(\.isHome)
        if homes.count > 1 {
            issues.append(.init(.error, .severalHomes(homes.map(\.name)), path: "/boards"))
        }

        for (b, board) in doc.boards.enumerated() {
            let bPath = "/boards/\(b)"
            let bName = ConfigSubject.board(board.name)
            if !boardIDs.insert(board.id).inserted {
                issues.append(.init(.error, .duplicateBoardID(bName), path: bPath + "/id"))
            }
            if board.rows * board.columns < 2 {
                issues.append(.init(.error, .boardTooSmall(bName), path: bPath))
            }

            var occupied: [String: HumTile] = [:]
            for (t, tile) in board.tiles.enumerated() {
                let tPath = "\(bPath)/tiles/\(t)"
                // A tile with no words or label is named by its place ("Tile 3 on 'Home'"), never "Tile ''".
                let name = [tile.label, tile.spokenText].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let tName = name.map(ConfigSubject.tile) ?? .tileNumber(t + 1, boardName: board.name, boardNumber: b + 1)
                if !tileIDs.insert(tile.id).inserted {
                    issues.append(.init(.error, .duplicateTileID(tName), path: tPath + "/id"))
                }
                // Folder tiles may be silent (they just open their board), but then they need a label.
                if tile.spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if tile.linkedBoardID == nil {
                        issues.append(.init(.error, .noWords(tName), path: tPath + "/spokenText"))
                    } else if tile.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        issues.append(.init(.error, .folderNeedsLabel(board: bName), path: tPath + "/label"))
                    }
                }
                if !(0..<board.rows).contains(tile.row) || !(0..<board.columns).contains(tile.column) {
                    issues.append(.init(.error, .outsideGrid(tName, board: bName, row: tile.row, column: tile.column, rows: board.rows, columns: board.columns), path: tPath))
                } else {
                    let slot = "\(tile.row),\(tile.column)"
                    if let other = occupied[slot] {
                        issues.append(.init(.error, .sameSpot(tName, otherTile: other.label, row: tile.row, column: tile.column, board: bName), path: tPath))
                    } else {
                        occupied[slot] = tile
                    }
                }
                if let link = tile.linkedBoardID, doc.board(withID: link) == nil {
                    // A warning, not an error: a single-board export may link to boards in the full setup.
                    issues.append(.init(.warning, .missingLink(tName), path: tPath + "/linkedBoardID"))
                }
                if tile.imageCredit != nil && tile.image == nil {
                    issues.append(.init(.warning, .creditWithoutPicture(tName), path: tPath + "/imageCredit"))
                }
                if let phrase = GLPRules.discouragedPhrase(in: tile.spokenText) ?? GLPRules.discouragedPhrase(in: tile.label) {
                    issues.append(.init(.warning, .praisePhrase(tName, phrase: phrase), path: tPath))
                }
            }
        }

        return issues
    }
}
