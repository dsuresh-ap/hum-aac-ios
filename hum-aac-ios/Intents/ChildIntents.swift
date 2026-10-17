// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import SwiftData

// Child-facing Shortcuts and Siri actions: say a tile's phrase, or open a board. They only read boards;
// nothing here adds, moves or renames a tile. Both open Hum, so sound comes from the app's own voice
// and the child lands on a board they know.

/// A tile with something to say, as Shortcuts, Siri and the Action button see it.
struct TileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Hum Tile"
    static let defaultQuery = TileQuery()

    let id: UUID
    let label: String
    let spokenText: String
    let boardName: String

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource = spokenText.isEmpty ? "Recorded voice · \(boardName)" : "“\(spokenText)” · \(boardName)"
        return DisplayRepresentation(title: "\(label)", subtitle: subtitle)
    }

    init(_ tile: Tile) {
        id = tile.id
        label = tile.label.isEmpty ? tile.spokenText : tile.label
        spokenText = tile.spokenText
        boardName = tile.board?.name ?? ""
    }
}

struct TileQuery: EntityStringQuery {
    @Dependency private var model: AppModel

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TileEntity] {
        let wanted = Set(identifiers)
        return try IntentStore.tiles(model.context).filter { wanted.contains($0.id) }.map(TileEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [TileEntity] {
        try IntentStore.speakingTiles(model.context)
            .filter { $0.label.localizedCaseInsensitiveContains(string) || $0.spokenText.localizedCaseInsensitiveContains(string) }
            .map(TileEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [TileEntity] {
        try IntentStore.speakingTiles(model.context).map(TileEntity.init)
    }
}

/// A board (Home or a folder's board).
struct BoardEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Hum Board"
    static let defaultQuery = BoardQuery()

    let id: UUID
    let name: String
    let isHome: Bool

    var displayRepresentation: DisplayRepresentation {
        isHome ? DisplayRepresentation(title: "\(name)", subtitle: "Home") : DisplayRepresentation(title: "\(name)")
    }

    init(_ board: Board) {
        id = board.id
        name = board.name
        isHome = board.isHome
    }
}

struct BoardQuery: EntityStringQuery {
    @Dependency private var model: AppModel

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [BoardEntity] {
        let wanted = Set(identifiers)
        return try IntentStore.boards(model.context).filter { wanted.contains($0.id) }.map(BoardEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [BoardEntity] {
        try IntentStore.boards(model.context).filter { $0.name.localizedCaseInsensitiveContains(string) }.map(BoardEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [BoardEntity] {
        try IntentStore.boards(model.context).map(BoardEntity.init)
    }
}

struct SayPhraseIntent: AppIntent {
    static let title: LocalizedStringResource = "Say a Phrase"
    static let description = IntentDescription("Opens Hum and says one tile's phrase in the child's Hum voice.")
    static let openAppWhenRun = true

    @Parameter(title: "Tile")
    var tile: TileEntity

    @Dependency private var model: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Say \(\.$tile)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard await model.say(tileID: tile.id) else {
            throw IntentError.message("That tile isn't in Hum anymore, or has nothing to say.")
        }
        return .result()
    }
}

struct OpenBoardIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a Board"
    static let description = IntentDescription("Opens Hum on one board.")
    static let openAppWhenRun = true

    @Parameter(title: "Board")
    var board: BoardEntity

    @Dependency private var model: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$board) in Hum")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard model.showFromShortcut(boardID: board.id) else {
            throw IntentError.message("That board isn't in Hum anymore.")
        }
        return .result()
    }
}

/// Reads boards and tiles for the entity queries. Read-only.
@MainActor
enum IntentStore {
    static func boards(_ context: ModelContext) throws -> [Board] {
        let boards = try context.fetch(FetchDescriptor<Board>(sortBy: [SortDescriptor(\.createdAt)]))
        // Home first, then the rest in the order they were made.
        return boards.filter(\.isHome) + boards.filter { !$0.isHome }
    }

    static func tiles(_ context: ModelContext) throws -> [Tile] {
        try context.fetch(FetchDescriptor<Tile>())
    }

    /// Tiles on a board that say something, in board order (Home first) and reading order.
    static func speakingTiles(_ context: ModelContext) throws -> [Tile] {
        try boards(context).flatMap { board in
            board.placedTiles
                .filter { !$0.isHidden && (!$0.spokenText.isEmpty || $0.audioData != nil) }
                .sorted { ($0.row ?? 0, $0.column ?? 0) < ($1.row ?? 0, $1.column ?? 0) }
        }
    }
}
