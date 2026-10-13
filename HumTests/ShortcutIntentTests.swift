// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import Hum

/// "Say a Phrase" and "Open a Board" (Shortcuts, Siri, the Action button). They read boards and never change one.
@MainActor
@Suite("Shortcut actions")
struct ShortcutIntentTests {
    @Test func sayingATileAddsItToHistoryAndMovesNothing() async throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let tile = try #require(model.home.placedTiles.first { !$0.spokenText.isEmpty })
        #expect(await model.say(tileID: tile.id))
        #expect(model.history.recent(1).first?.spokenText == tile.spokenText)
        #expect(model.layout(model.home) == before)
    }

    @Test func sayingWorksWhileAGrownUpIsEditing() async throws {
        let model = makeModel()
        model.mode = .parent
        let tile = try #require(model.home.placedTiles.first { !$0.spokenText.isEmpty })
        #expect(await model.say(tileID: tile.id))
        #expect(model.mode == .parent)
    }

    @Test func missingTileSaysNothing() async {
        let model = makeModel()
        #expect(await model.say(tileID: UUID()) == false)
        #expect(model.history.recent(1).isEmpty)
    }

    @Test func openingABoardShowsItToTheChild() throws {
        let model = makeModel()
        let snack = try #require(model.home.placedTiles.first { $0.label == "snack" })
        let food = model.store.makeFolder(named: "Food", for: snack, rows: 2, columns: 3)
        model.goHome()
        #expect(model.showFromShortcut(boardID: food.id))
        #expect(model.currentBoardID == food.id)
        #expect(model.canGoBack)
    }

    @Test func openingABoardWhileEditingMovesTheEditorOnly() throws {
        let model = makeModel()
        let snack = try #require(model.home.placedTiles.first { $0.label == "snack" })
        let food = model.store.makeFolder(named: "Food", for: snack, rows: 2, columns: 3)
        model.goHome()
        model.mode = .parent
        #expect(model.showFromShortcut(boardID: food.id))
        #expect(model.editingBoardID == food.id)
        #expect(model.mode == .parent)
    }

    @Test func missingBoardOpensNothing() {
        let model = makeModel()
        #expect(model.showFromShortcut(boardID: UUID()) == false)
    }

    @Test func suggestionsAreSpeakingTilesHomeFirst() throws {
        let model = makeModel()
        let snack = try #require(model.home.placedTiles.first { $0.label == "snack" })
        let food = model.store.makeFolder(named: "Food", for: snack, rows: 2, columns: 3)
        let apple = try model.store.addTile(to: food, row: 0, column: 0, label: "apple", spokenText: "Let's have apple!")
        let hidden = try #require(model.home.placedTiles.first { !$0.spokenText.isEmpty && $0.id != snack.id })
        model.store.setHidden(hidden, true)
        let tiles = try IntentStore.speakingTiles(model.context)
        #expect(tiles.contains { $0.id == apple.id })
        #expect(!tiles.contains { $0.id == hidden.id })
        #expect(tiles.first?.board?.isHome == true)
        #expect(try IntentStore.boards(model.context).first?.isHome == true)
    }
}
