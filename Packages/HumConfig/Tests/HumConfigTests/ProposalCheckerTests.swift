// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import HumConfig

@Suite("AI proposal checks")
struct ProposalCheckerTests {
    let homeID = UUID()

    func existing(fill: Int = 1) -> HumDocument {
        var tiles: [HumTile] = []
        for i in 0..<fill {
            tiles.append(HumTile(label: "t\(i)", spokenText: i == 0 ? "No thank you" : "Tile \(i)", row: i / 2, column: i % 2, function: i == 0 ? .protest : .request))
        }
        return HumDocument(boards: [HumBoard(id: homeID, name: "Home", rows: 2, columns: 2, isHome: true, tiles: tiles)])
    }

    /// HUM-047: a suggestion with its own `boardName` makes a new folder, but no tile opens it, so the
    /// child can never reach those tiles. The folder should get a folder tile on the board being edited.
    @Test func suggestedTilesInANewFolderAreReachable() {
        let food = HumBoard(name: "Food", rows: 2, columns: 2, tiles: [])
        var setup = existing()
        setup.boards.append(food)
        let document = ProposalChecker.document(from: [
            .init(label: "all aboard", spokenText: "All aboard!", function: .request, boardName: "Trains"),
        ], targetBoardID: food.id, existing: setup)
        let trains = document.boards.first { $0.name == "Trains" }
        #expect(trains != nil, "The suggestion's own folder is made")
        let opener = document.boards.first { $0.id == food.id }?.tiles.first { $0.linkedBoardID == trains?.id }
        #expect(opener?.label == "Trains", "A folder tile on the board being edited opens it")
        #expect(trains?.tiles.map(\.spokenText) == ["All aboard!"])
    }

    /// HUM-047: two suggestions for the same new folder share one folder and one folder tile.
    @Test func oneNewFolderForManySuggestions() {
        let document = ProposalChecker.document(from: [
            .init(label: "all aboard", spokenText: "All aboard!", boardName: "Trains"),
            .init(label: "choo choo", spokenText: "Choo choo!", boardName: "trains"),
        ], targetBoardID: homeID, existing: existing())
        #expect(document.boards.count == 2)
        #expect(document.boards.flatMap(\.tiles).filter { $0.linkedBoardID != nil }.count == 1)
    }

    /// HUM-047: a board the child can't reach from here (e.g. "Home" while editing Food) doesn't pull
    /// tiles away from the board being edited; a folder this board opens does.
    @Test func namedBoardsOnlyWinWhenReachable() {
        let food = HumBoard(name: "Food", rows: 2, columns: 2, tiles: [])
        let drinks = HumBoard(name: "Drinks", rows: 2, columns: 2, tiles: [])
        var foodWithDrinks = food
        foodWithDrinks.tiles = [HumTile(label: "drinks", spokenText: "", row: 0, column: 0, linkedBoardID: drinks.id)]
        var setup = existing()
        setup.boards += [foodWithDrinks, drinks]
        let document = ProposalChecker.document(from: [
            .init(label: "crackers", spokenText: "Let's have crackers", boardName: "Home"),
            .init(label: "juice", spokenText: "Juice please", boardName: "Drinks"),
            .init(label: "stop", spokenText: "Stop it", function: .protest, boardName: "Home"),
        ], targetBoardID: food.id, existing: setup)
        func board(_ text: String) -> UUID? { document.boards.first { $0.tiles.contains { $0.spokenText == text } }?.id }
        #expect(board("Let's have crackers") == food.id)
        #expect(board("Juice please") == drinks.id)
        #expect(board("Stop it") == homeID)
    }

    /// HUM-018: labels don't end on a dangling small word.
    @Test(arguments: [
        ("Let's go to the park!", "Let's go"),
        ("I need a break.", "I need a break"),
        ("Can I have some more juice please", "Can I have"),
        ("Help!", "Help"),
    ])
    func shortLabelsEndOnARealWord(phrase: String, expected: String) {
        #expect(ProposalChecker.shortLabel(for: phrase) == expected)
    }

    /// HUM-047: with no `boardName`, suggestions go to the board being edited, not Home.
    @Test func suggestionsGoToTheBoardBeingEdited() {
        let food = HumBoard(name: "Food", rows: 2, columns: 2, tiles: [])
        var setup = existing()
        setup.boards.append(food)
        let document = ProposalChecker.document(from: [.init(label: "crackers", spokenText: "Let's have crackers")],
                                                targetBoardID: food.id, existing: setup)
        #expect(document.boards.map(\.id) == [food.id])
    }

    @Test func praiseAndComplianceAreRemoved() {
        let result = ProposalChecker.check([
            .init(label: "yay", spokenText: "Good job!"),
            .init(label: "hands", spokenText: "Quiet hands please"),
            .init(label: "train", spokenText: "All aboard!"),
        ], parentPhrases: [], existing: existing())
        #expect(result.tiles.map(\.spokenText) == ["All aboard!"])
        #expect(result.notes.count == 2)
    }

    @Test func splitGestaltIsRejoined() {
        let result = ProposalChecker.check([
            .init(label: "let's get", spokenText: "Let's get"),
            .init(label: "out", spokenText: "out of here!"),
        ], parentPhrases: ["Let's get out of here!"], existing: existing())
        #expect(result.tiles.map(\.spokenText) == ["Let's get out of here!"])
    }

    @Test func duplicatesOfExistingTilesAreDropped() {
        let result = ProposalChecker.check([.init(label: "no", spokenText: "no thank you!")], parentPhrases: [], existing: existing())
        #expect(result.tiles.isEmpty)
    }

    @Test func longLabelsAreShortened() {
        let result = ProposalChecker.check([.init(label: "", spokenText: "To infinity and beyond, let's go fast!")], parentPhrases: [], existing: existing())
        #expect(result.tiles.first?.label == "To infinity and beyond")
    }

    @Test func protestOnSubBoardIsAlsoOfferedOnHome() {
        let result = ProposalChecker.check([.init(label: "stop", spokenText: "Stop the train!", function: .protest, boardName: "Trains")], parentPhrases: [], existing: existing())
        #expect(result.tiles.count == 2)
        #expect(result.tiles.contains { $0.boardName == "Home" })
    }

    @Test func documentOnlyAddsAndNothingMoves() {
        let base = existing(fill: 3)
        let checked = ProposalChecker.check([
            .init(label: "a", spokenText: "All aboard!"),
            .init(label: "b", spokenText: "Choo choo!"),
            .init(label: "c", spokenText: "The end!"),
        ], parentPhrases: [], existing: base)
        let doc = ProposalChecker.document(from: checked.tiles, targetBoardID: homeID, existing: base)
        #expect(HumValidator.semanticIssues(in: doc).filter { $0.severity == .error }.isEmpty)
        let plan = MergePlanner.plan(existing: base, incoming: doc, mode: .merge)
        #expect(plan.summary.movedTiles == 0)
        #expect(plan.summary.removedTiles == 0)
        #expect(plan.summary.newTiles == 3)
        #expect(plan.unplaced.count == 2)  // only one free spot on a 2×2 board with 3 tiles
        #expect(plan.summary.sentence.contains("No tiles will move."))
    }

    @Test func newBoardNameCreatesSubBoard() {
        let checked = ProposalChecker.check([.init(label: "all aboard", spokenText: "All aboard!", boardName: "Trains")], parentPhrases: [], existing: existing())
        let doc = ProposalChecker.document(from: checked.tiles, targetBoardID: nil, existing: existing())
        // The new folder, and Home (the board being edited) with a tile that opens it.
        #expect(doc.boards.map(\.name) == ["Home", "Trains"])
        #expect(doc.boards[0].tiles.map(\.linkedBoardID) == [doc.boards[1].id])
    }
}
