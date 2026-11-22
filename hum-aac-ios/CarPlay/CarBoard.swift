// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData
import HumConfig

/// The boards Hum shows on a car's screen through CarPlay, for someone who drives and uses Hum to talk:
/// at a traffic stop, a toll booth, with a parking attendant or after a crash. They tap the car's
/// screen, with their hands in sight, instead of reaching for a phone.
///
/// CarPlay draws its own grid of at most 8 buttons, so each board shows its first 8 tiles in reading
/// order. Several boards become tabs. A folder tile on a tab opens its folder; inside a folder, folder
/// tiles only speak (driving task apps may only go two screens deep). The boards are chosen per iPhone in
/// Settings; with none chosen it's Home.
enum CarBoard {
    /// CarPlay's own limit (`CPGridTemplateMaximumItems`).
    static let maximumTiles = 8
    /// How many boards Settings lets a parent choose. A car may allow fewer tabs; then it shows the
    /// first ones (the About me card takes a tab too).
    static let maximumBoards = 4

    /// CarPlay is iPhone only. Apple granted Hum the driving task entitlement
    /// (hum-aac-ios-iphone.entitlements, used by every iPhone and iPad build); the Mac has no CarPlay.
    static var isAvailable: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// The chosen boards that still exist, in the chosen order. With none, Home (or the oldest board).
    @MainActor
    static func boards(in model: AppModel) -> [Board] {
        let all = model.store.boards()
        let chosen = model.settings.carBoardIDs.compactMap { id in all.first { $0.id == id } }
        if !chosen.isEmpty { return Array(chosen.prefix(maximumBoards)) }
        let home = all.first(where: \.isHome) ?? all.sorted { $0.createdAt < $1.createdAt }.first
        return home.map { [$0] } ?? []
    }

    /// The tiles the car shows: on the board, not hidden, in reading order, that speak or open one of
    /// `openable` (folders the car may open from here; empty inside a folder).
    static func tiles(on board: Board, openable: Set<UUID> = []) -> [Tile] {
        Array(useful(on: board, openable: openable).prefix(maximumTiles))
    }

    /// Tiles that would work in the car but don't fit.
    static func tilesLeftOut(on board: Board, openable: Set<UUID> = []) -> Int {
        max(useful(on: board, openable: openable).count - maximumTiles, 0)
    }

    /// The board a tile opens in the car, if it may open one from here.
    static func opens(_ tile: Tile, openable: Set<UUID>) -> UUID? {
        tile.linkedBoardID.flatMap { openable.contains($0) ? $0 : nil }
    }

    static func speaks(_ tile: Tile) -> Bool { !tile.spokenText.isEmpty || tile.audioData != nil }

    private static func useful(on board: Board, openable: Set<UUID>) -> [Tile] {
        board.placedTiles
            .filter { !$0.isHidden && (speaks($0) || opens($0, openable: openable.subtracting([board.id])) != nil) }
            .sorted { ($0.row ?? 0, $0.column ?? 0) < ($1.row ?? 0, $1.column ?? 0) }
    }

    /// Two ready-made boards, "Traffic stop" and "After a crash", chosen for CarPlay in that order. The
    /// phrases are only a start: the driver (or a parent) changes them like any other tile. Yes and No
    /// sit in the same spots on both, so the hand finds them without looking. English for now, like the
    /// starter board.
    @MainActor
    @discardableResult
    static func makeStarterBoards(in model: AppModel) -> [Board] {
        typealias Item = (label: String, phrase: String, symbol: String, function: TileFunction?)
        let boards: [(name: String, tiles: [Item])] = [
            (String(localized: "Traffic stop", comment: "Name of a board Hum makes for CarPlay."), [
                ("can't speak", "I can't speak right now. I use this app to talk.", "💬", .comment),
                ("autistic", "I'm autistic.", "♾️", .comment),
                ("a moment", "Please give me a moment.", "⏳", .regulation),
                ("license", "My license is in my wallet.", "🪪", .comment),
                ("reaching", "I'm going to reach for it now.", "✋", .comment),
                ("I understand", "I understand you.", "👂", .connection),
                ("yes", "Yes.", "✅", .connection),
                ("no", "No.", "❌", .protest),
            ]),
            (String(localized: "After a crash", comment: "Name of a board Hum makes for CarPlay."), [
                ("can't speak", "I can't speak right now. I use this app to talk.", "💬", .comment),
                ("not hurt", "I'm not hurt.", "🙂", .comment),
                ("hurt", "I'm hurt.", "🤕", .request),
                ("ambulance", "Please call an ambulance.", "🚑", .request),
                ("police", "Please call the police.", "🚓", .request),
                ("my contact", "Please call my emergency contact.", "📞", .request),
                ("yes", "Yes.", "✅", .connection),
                ("no", "No.", "❌", .protest),
            ]),
        ]
        let makeHome = model.store.boards().isEmpty
        var made: [Board] = []
        // One undo step for both boards and their tiles.
        model.store.change("New Board") {
            for (index, spec) in boards.enumerated() {
                let board = Board(name: spec.name, rows: 2, columns: 4, isHome: makeHome && index == 0)
                model.context.insert(board)
                for (i, item) in spec.tiles.enumerated() {
                    let tile = Tile(label: item.label, spokenText: item.phrase, row: i / 4, column: i % 4)
                    model.context.insert(tile)
                    tile.board = board
                    tile.symbol = item.symbol
                    tile.function = item.function
                }
                made.append(board)
            }
        }
        model.settings.carBoardIDs = made.map(\.id)
        return made
    }
}

/// The app's one model, for the CarPlay scene. UIKit makes the scene delegate by class name, so it
/// can't be handed the model; HumApp sets this at launch.
@MainActor
enum CarPlayHost {
    static var model: AppModel?
}
