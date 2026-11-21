// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData
import HumConfig

/// The board Hum shows on a car's screen through CarPlay, for someone who drives and uses Hum to talk:
/// at a traffic stop, a toll booth, with a parking attendant or after a crash. They tap the car's
/// screen, with their hands in sight, instead of reaching for a phone.
///
/// CarPlay draws its own grid of at most 8 buttons, so the car shows the first 8 tiles of one board in
/// reading order. Folders don't open there (CarPlay apps may only go one screen deep), but their phrase
/// still speaks. The board is chosen per iPhone in Settings; with none chosen it's Home.
enum CarBoard {
    /// CarPlay's own limit (`CPGridTemplateMaximumItems`).
    static let maximumTiles = 8

    /// Apple has to grant Hum a CarPlay entitlement before it can run in a car. Until then the car
    /// settings only show in the Simulator, where the CarPlay window works without it.
    /// When Apple grants it: add the entitlement to hum-aac-ios.entitlements and make this `true`.
    static var isAvailable: Bool {
        #if os(iOS) && targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// The chosen board, or Home if none is chosen or it was deleted.
    @MainActor
    static func board(in model: AppModel) -> Board? {
        let boards = model.store.boards()
        if let id = model.settings.carBoardID, let chosen = boards.first(where: { $0.id == id }) { return chosen }
        return boards.first(where: \.isHome) ?? boards.sorted { $0.createdAt < $1.createdAt }.first
    }

    /// The tiles the car shows: on the board, not hidden, with something to say, in reading order.
    static func tiles(on board: Board) -> [Tile] {
        let speaking = board.placedTiles
            .filter { !$0.isHidden && (!$0.spokenText.isEmpty || $0.audioData != nil) }
            .sorted { ($0.row ?? 0, $0.column ?? 0) < ($1.row ?? 0, $1.column ?? 0) }
        return Array(speaking.prefix(maximumTiles))
    }

    /// Tiles that would speak on the board but don't fit in the car.
    static func tilesLeftOut(on board: Board) -> Int {
        let speaking = board.placedTiles.filter { !$0.isHidden && (!$0.spokenText.isEmpty || $0.audioData != nil) }
        return max(speaking.count - maximumTiles, 0)
    }

    /// A ready-made "In the car" board, chosen for CarPlay. The phrases are only a start: the person (or
    /// a parent) changes them like any other tile. English for now, like the starter board.
    @MainActor
    @discardableResult
    static func makeStarterBoard(in model: AppModel) -> Board {
        let board = Board(name: String(localized: "In the car", comment: "Name of the board Hum makes for CarPlay."),
                          rows: 2, columns: 4, isHome: model.store.boards().isEmpty)
        let tiles: [(label: String, phrase: String, symbol: String, function: TileFunction?)] = [
            ("can't speak", "I can't speak right now. I use this app to talk.", "💬", .comment),
            ("autistic", "I'm autistic.", "♾️", .comment),
            ("a moment", "Please give me a moment.", "⏳", .regulation),
            ("license", "My license is in my wallet.", "🪪", .comment),
            ("reaching", "I'm going to reach for it now.", "✋", .comment),
            ("I understand", "I understand you.", "👂", .connection),
            ("yes", "Yes.", "✅", .connection),
            ("no", "No.", "❌", .protest),
        ]
        // One undo step for the board and its tiles.
        model.store.change("New Board") {
            model.context.insert(board)
            for (i, item) in tiles.enumerated() {
                let tile = Tile(label: item.label, spokenText: item.phrase, row: i / 4, column: i % 4)
                model.context.insert(tile)
                tile.board = board
                tile.symbol = item.symbol
                tile.function = item.function
            }
        }
        model.settings.carBoardID = board.id
        return board
    }
}

/// The app's one model, for the CarPlay scene. UIKit makes the scene delegate by class name, so it
/// can't be handed the model; HumApp sets this at launch.
@MainActor
enum CarPlayHost {
    static var model: AppModel?
}
