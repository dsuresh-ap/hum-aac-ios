// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import HumConfig
import SwiftData

/// Hum's built-in starter board (`starter.hum.json`), so sync can tell it apart from a family's own Home.
@MainActor
enum StarterBoard {
    /// The starter's bundled document, or nil if the file is missing.
    static let document: HumDocument? = {
        guard let url = Bundle.main.url(forResource: "starter.hum", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? HumConfigLoader.load(data).document
    }()

    /// The starter Home's fixed id (the same on every device).
    static var homeID: UUID? { document?.homeBoard?.id }

    /// True if `board` is the starter Home exactly as Hum made it: same size, the same tiles in the same
    /// spots with the same words, and no photos or recordings added. Such a board has no family work in it.
    static func isUntouched(_ board: Board) -> Bool {
        guard let starter = document?.homeBoard, board.id == starter.id,
              board.rows == starter.rows, board.columns == starter.columns else { return false }
        let tiles = (board.tiles ?? []).filter { !$0.isDeleted }
        guard tiles.count == starter.tiles.count else { return false }
        let expected = Dictionary(uniqueKeysWithValues: starter.tiles.map { ($0.id, $0) })
        return tiles.allSatisfy { tile in
            guard let original = expected[tile.id] else { return false }
            return tile.label == original.label && tile.spokenText == original.spokenText
                && tile.row == original.row && tile.column == original.column
                && tile.linkedBoardID == original.linkedBoardID && tile.isHidden == original.hidden
                && tile.imageData == nil && tile.audioData == nil
        }
    }
}
