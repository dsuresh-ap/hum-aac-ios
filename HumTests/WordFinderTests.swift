// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import NaturalLanguage
import Testing
@testable import Hum

/// The word finder finds tiles and folders, shows the way from Home, and never speaks or moves a tile.
@MainActor
@Suite("Word finder")
struct WordFinderTests {
    /// Home with a "snack" folder that opens Food, which holds apple and juice.
    private func modelWithFood() throws -> (AppModel, food: Board, folder: Tile, apple: Tile) {
        let model = makeModel()
        let snack = try #require(model.home.placedTiles.first { $0.label == "snack" })
        let food = model.store.makeFolder(named: "Food", for: snack, rows: 2, columns: 3)
        let apple = try model.store.addTile(to: food, row: 0, column: 0, label: "apple", spokenText: "Let's have apple!")
        _ = try model.store.addTile(to: food, row: 0, column: 1, label: "juice", spokenText: "Juice please")
        model.goHome()
        return (model, food, snack, apple)
    }

    @Test func findsATileInAFolderWithTheWayThere() throws {
        let (model, food, folder, apple) = try modelWithFood()
        let result = try #require(WordFinder(boards: model.store.boards()).search("apple").first)
        #expect(result.id == apple.id && !result.related)
        #expect(result.path == [model.home.name, "Food"])
        #expect(result.route == [.init(boardID: model.home.id, tileID: folder.id), .init(boardID: food.id, tileID: apple.id)])
    }

    @Test func matchesSpokenTextIgnoringCaseAndPunctuation() throws {
        let (model, _, _, apple) = try modelWithFood()
        let results = WordFinder(boards: model.store.boards()).search("LETS HAVE")
        #expect(results.contains { $0.id == apple.id })
    }

    @Test func findsFoldersByName() throws {
        let (model, food, _, _) = try modelWithFood()
        let result = try #require(WordFinder(boards: model.store.boards()).search("foo").first)
        #expect(result.kind == .board && result.id == food.id)
        #expect(result.path == [model.home.name])
    }

    @Test func labelStartRanksBeforeAMatchInside() {
        let home = UUID()
        let finder = WordFinder(boards: [.init(id: home, name: "Home", isHome: true)], tiles: [
            .init(tileID: UUID(), boardID: home, label: "pineapple", spokenText: "", symbol: nil, linkedBoardID: nil, isHidden: false),
            .init(tileID: UUID(), boardID: home, label: "apple", spokenText: "", symbol: nil, linkedBoardID: nil, isHidden: false),
        ])
        #expect(finder.search("apple", relatedLimit: 0).map(\.label) == ["apple", "pineapple"])
    }

    @Test func hiddenTilesAreNeverFound() throws {
        let (model, _, _, apple) = try modelWithFood()
        model.store.setHidden(apple, true)
        #expect(!WordFinder(boards: model.store.boards()).search("apple").contains { $0.id == apple.id })
    }

    @Test func relatedMeaningsComeAfterExactMatches() throws {
        try #require(NLEmbedding.wordEmbedding(for: .english) != nil)
        let home = UUID()
        func tile(_ label: String) -> WordFinder.Entry {
            .init(tileID: UUID(), boardID: home, label: label, spokenText: label, symbol: nil, linkedBoardID: nil, isHidden: false)
        }
        let finder = WordFinder(boards: [.init(id: home, name: "Home", isHome: true)],
                                tiles: [tile("car"), tile("It's too loud"), tile("crackers"), tile("vehicle sticker")])
        let results = finder.search("vehicle")
        #expect(results.first?.label == "vehicle sticker" && results.first?.related == false)
        #expect(results.contains { $0.label == "car" && $0.related })
        #expect(!results.contains { $0.label == "crackers" })
    }

    @Test func childIsGuidedStepByStepAndNothingSpeaks() throws {
        let (model, food, folder, apple) = try modelWithFood()
        let result = try #require(WordFinder(boards: model.store.boards()).search("apple").first)
        model.startFinding(result)
        #expect(model.finderHint == .tile(folder.id))
        #expect(model.history.recent(1).isEmpty)
        let folderCell = try #require(model.snapshot?.cells.joined().compactMap { $0 }.first { $0.id == folder.id })
        model.tap(folderCell, tapTime: 0)
        #expect(model.currentBoardID == food.id)
        #expect(model.finderHint == .tile(apple.id))
        let appleCell = try #require(model.snapshot?.cells.joined().compactMap { $0 }.first { $0.id == apple.id })
        model.tap(appleCell, tapTime: 0)
        #expect(model.finderHint == nil && model.finderTarget == nil)
    }

    @Test func offTheWayTheHomeButtonGlows() throws {
        let (model, food, _, apple) = try modelWithFood()
        let other = try #require(model.home.placedTiles.first { $0.linkedBoardID == nil && $0.id != apple.id })
        let elsewhere = model.store.makeFolder(named: "Toys", for: other, rows: 2, columns: 2)
        let result = try #require(WordFinder(boards: model.store.boards()).search("apple").first)
        model.startFinding(result)
        model.open(boardID: elsewhere.id)
        #expect(model.finderHint == .home)
        #expect(food.id != elsewhere.id)
    }

    @Test func editorFindOpensTheBoardAndRingsTheTile() throws {
        let (model, food, _, apple) = try modelWithFood()
        model.mode = .parent
        let result = try #require(WordFinder(boards: model.store.boards()).search("apple").first)
        model.showInEditor(result)
        #expect(model.editingBoardID == food.id)
        #expect(model.editorHighlightID == apple.id)
    }
}
