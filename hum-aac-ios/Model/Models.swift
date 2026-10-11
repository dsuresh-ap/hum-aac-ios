// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData
import HumConfig

// SwiftData models. They are CloudKit-compatible from day one, so iCloud sync (M4) needs no migration:
// - every attribute is optional or has a default
// - no @Attribute(.unique) (CloudKit can't enforce it; we dedupe by `id` in code)
// - every relationship is optional, with no `.deny` delete rules
// - media is `.externalStorage` Data, which syncs as CKAsset

@Model
final class Board {
    /// Stable config ID. Matches `HumBoard.id` in hum.json. Not unique-constrained (see above).
    var id: UUID = UUID()
    var name: String = ""
    var rows: Int = 3
    var columns: Int = 3
    var isHome: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Unknown fields from imported files, kept so export gives them back.
    var extraJSON: Data?

    @Relationship(deleteRule: .cascade, inverse: \Tile.board)
    var tiles: [Tile]? = []

    init(id: UUID = UUID(), name: String, rows: Int, columns: Int, isHome: Bool = false) {
        self.id = id
        self.name = name
        self.rows = rows
        self.columns = columns
        self.isHome = isHome
    }

    /// Tiles that have a spot on the grid.
    var placedTiles: [Tile] { (tiles ?? []).filter { $0.row != nil && $0.column != nil } }
    /// New tiles from an import, AI or sync conflict that are waiting for the parent to place them.
    var unplacedTiles: [Tile] { (tiles ?? []).filter { $0.row == nil || $0.column == nil } }
}

@Model
final class Tile {
    var id: UUID = UUID()
    /// Short text shown on the tile.
    var label: String = ""
    /// What the tile says: one whole gestalt. Never split into words.
    var spokenText: String = ""
    var functionRaw: String?
    var colorHex: String?
    /// A plain UUID instead of a relationship: no cycles, and a deleted board just makes the link inert.
    var linkedBoardID: UUID?
    var isHidden: Bool = false
    /// `nil` means unplaced. An unplaced tile is never shown to the child.
    var row: Int?
    var column: Int?
    /// Only changed by an explicit parent move. Used to settle sync conflicts deterministically.
    var positionUpdatedAt: Date = Date.now
    /// Placeholder emoji until the parent adds a photo.
    var symbol: String?
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var audioData: Data?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var extraJSON: Data?
    var board: Board?

    init(id: UUID = UUID(), label: String, spokenText: String, row: Int?, column: Int?) {
        self.id = id
        self.label = label
        self.spokenText = spokenText
        self.row = row
        self.column = column
    }

    var function: TileFunction? {
        get { functionRaw.flatMap(TileFunction.init(rawValue:)) }
        set { functionRaw = newValue?.rawValue }
    }
}

enum HumSchema {
    static let models: [any PersistentModel.Type] = [Board.self, Tile.self]
}
