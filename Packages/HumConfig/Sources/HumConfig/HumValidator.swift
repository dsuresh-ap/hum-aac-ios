// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Checks that need more than the JSON Schema: unique IDs, grid placement, links, and GLP rules.
public enum HumValidator {
    /// Supported grid sizes (inclusive). 1×2 up to 6×8 per the product spec.
    public static let rowRange = 1...8
    public static let columnRange = 1...8

    public static func semanticIssues(in doc: HumDocument) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var boardIDs: Set<UUID> = []
        var tileIDs: Set<UUID> = []

        let homes = doc.boards.filter(\.isHome)
        if homes.count > 1 {
            issues.append(.init(.error, "More than one board is marked as Home (\(homes.map { "'\($0.name)'" }.joined(separator: ", "))). Only one can be Home.", path: "/boards"))
        }

        for (b, board) in doc.boards.enumerated() {
            let bPath = "/boards/\(b)"
            let bName = "Board '\(board.name)'"
            if !boardIDs.insert(board.id).inserted {
                issues.append(.init(.error, "\(bName) has the same ID as another board. Every board needs its own ID.", path: bPath + "/id"))
            }
            if board.rows * board.columns < 2 {
                issues.append(.init(.error, "\(bName) is too small. The smallest grid is 1 × 2.", path: bPath))
            }

            var occupied: [String: HumTile] = [:]
            for (t, tile) in board.tiles.enumerated() {
                let tPath = "\(bPath)/tiles/\(t)"
                let tName = "Tile '\(tile.label.isEmpty ? tile.spokenText : tile.label)'"
                if !tileIDs.insert(tile.id).inserted {
                    issues.append(.init(.error, "\(tName) has the same ID as another tile. Every tile needs its own ID.", path: tPath + "/id"))
                }
                // Folder tiles may be silent (they just open their board), but then they need a label.
                if tile.spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if tile.linkedBoardID == nil {
                        issues.append(.init(.error, "\(tName) has no words to say.", path: tPath + "/spokenText"))
                    } else if tile.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        issues.append(.init(.error, "A folder tile on \(bName) needs a label or words to say.", path: tPath + "/label"))
                    }
                }
                if !(0..<board.rows).contains(tile.row) || !(0..<board.columns).contains(tile.column) {
                    issues.append(.init(.error, "\(tName) is outside the grid of \(bName) (row \(tile.row), column \(tile.column); the grid is \(board.rows) rows × \(board.columns) columns, counting from 0).", path: tPath))
                } else {
                    let slot = "\(tile.row),\(tile.column)"
                    if let other = occupied[slot] {
                        issues.append(.init(.error, "\(tName) and tile '\(other.label)' are in the same spot (row \(tile.row), column \(tile.column)) on \(bName).", path: tPath))
                    } else {
                        occupied[slot] = tile
                    }
                }
                if let link = tile.linkedBoardID, doc.board(withID: link) == nil {
                    // A warning, not an error: a single-board export may link to boards in the full setup.
                    issues.append(.init(.warning, "\(tName) opens a board that isn't in this file. It will still speak; the link is ignored until that board exists.", path: tPath + "/linkedBoardID"))
                }
                if tile.imageCredit != nil && tile.image == nil {
                    issues.append(.init(.warning, "\(tName) has a picture credit but no picture. The credit is kept, but it has nothing to describe.", path: tPath + "/imageCredit"))
                }
                if let phrase = GLPRules.discouragedPhrase(in: tile.spokenText) ?? GLPRules.discouragedPhrase(in: tile.label) {
                    issues.append(.init(.warning, "\(tName) uses \"\(phrase)\". Hum avoids praise, reward and compliance phrases. Tiles are the child's voice.", path: tPath))
                }
            }
        }

        // Protest and regulation tiles belong on Home, where they can always be reached.
        // A copy on a sub-board is fine as long as the same phrase is also on Home.
        if let home = doc.homeBoard {
            let onHome = Set(home.tiles.map { GLPRules.normalize($0.spokenText) })
            for (b, board) in doc.boards.enumerated() where board.id != home.id {
                for (t, tile) in board.tiles.enumerated() where !onHome.contains(GLPRules.normalize(tile.spokenText)) {
                    if let f = tile.function, GLPRules.mustStayOnHome.contains(f) {
                        issues.append(.init(.warning, "Tile '\(tile.label)' (\(f.rawValue)) is on '\(board.name)'. Protest and regulation tiles should also be on Home so they can always be reached.", path: "/boards/\(b)/tiles/\(t)"))
                    }
                }
            }
        }
        return issues
    }
}
