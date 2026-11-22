// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import HumConfig
@testable import Hum

/// The boards CarPlay shows (CarPlay/CarBoard.swift): Home unless some are chosen, at most 8 tiles each,
/// in reading order. Choosing or making them never moves a tile.
@MainActor
@Suite("Car board")
struct CarBoardTests {
    @Test func homeUntilBoardsAreChosen() throws {
        let model = makeModel()
        #expect(CarBoard.boards(in: model).map(\.id) == [model.home.id])
        let errands = model.store.createBoard(name: "Errands", rows: 2, columns: 2)
        let fuel = model.store.createBoard(name: "Fuel", rows: 2, columns: 2)
        model.settings.carBoardIDs = [fuel.id, errands.id]
        // The chosen order is the tab order.
        #expect(CarBoard.boards(in: model).map(\.id) == [fuel.id, errands.id])
    }

    @Test func deletedCarBoardsAreSkipped() throws {
        let model = makeModel()
        let errands = model.store.createBoard(name: "Errands", rows: 2, columns: 2)
        let fuel = model.store.createBoard(name: "Fuel", rows: 2, columns: 2)
        model.settings.carBoardIDs = [errands.id, fuel.id]
        try model.store.delete(errands)
        #expect(CarBoard.boards(in: model).map(\.id) == [fuel.id])
        try model.store.delete(fuel)
        #expect(CarBoard.boards(in: model).map(\.id) == [model.home.id])
    }

    @Test func atMostFourBoards() throws {
        let model = makeModel()
        let made = (0..<6).map { model.store.createBoard(name: "B\($0)", rows: 1, columns: 1) }
        model.settings.carBoardIDs = made.map(\.id)
        #expect(CarBoard.boards(in: model).map(\.id) == made.prefix(CarBoard.maximumBoards).map(\.id))
    }

    @Test func showsTheFirstEightTilesInReadingOrder() throws {
        let model = makeModel()
        let board = model.store.createBoard(name: "Big", rows: 3, columns: 4)
        // Added out of order, so the order comes from the spots, not from when they were made.
        for spot in [(2, 3), (0, 1), (1, 0), (0, 0), (2, 0), (1, 2), (0, 3), (1, 1), (2, 2), (0, 2)] {
            try model.store.addTile(to: board, row: spot.0, column: spot.1, label: "\(spot.0)\(spot.1)", spokenText: "Tile \(spot.0)\(spot.1)")
        }
        let hidden = try #require(board.placedTiles.first { $0.label == "00" })
        model.store.setHidden(hidden, true)

        let shown = CarBoard.tiles(on: board).map(\.label)
        #expect(shown == ["01", "02", "03", "10", "11", "12", "20", "22"])
        #expect(CarBoard.tilesLeftOut(on: board) == 1)
    }

    @Test func aSilentFolderTileShowsOnlyWhereItCanOpen() throws {
        let model = makeModel()
        let board = model.store.createBoard(name: "Mine", rows: 1, columns: 3)
        let food = model.store.createBoard(name: "Food", rows: 1, columns: 1)
        let folder = try model.store.addTile(to: board, row: 0, column: 0, label: "food", spokenText: "")
        folder.linkedBoardID = food.id
        let gone = try model.store.addTile(to: board, row: 0, column: 1, label: "gone", spokenText: "")
        gone.linkedBoardID = UUID()
        // On a tab it opens Food. Inside a folder (nothing openable) a silent folder tile has nothing to do.
        #expect(CarBoard.tiles(on: board, openable: [food.id]).map(\.id) == [folder.id])
        #expect(CarBoard.opens(folder, openable: [food.id]) == food.id)
        #expect(CarBoard.tiles(on: board).isEmpty)
        // A tile never opens the board it's on.
        let back = try model.store.addTile(to: food, row: 0, column: 0, label: "loop", spokenText: "")
        back.linkedBoardID = food.id
        #expect(CarBoard.tiles(on: food, openable: [food.id]).isEmpty)
    }

    @Test func aRecordedTileWithNoWordsStillShows() throws {
        let model = makeModel()
        let board = model.store.createBoard(name: "Mine", rows: 1, columns: 2)
        let recorded = try model.store.addTile(to: board, row: 0, column: 0, label: "mine", spokenText: "")
        recorded.audioData = Data([1, 2, 3])
        #expect(CarBoard.tiles(on: board).map(\.id) == [recorded.id])
    }

    @Test func theStarterBoardsAreChosenAndLeaveOtherBoardsAlone() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let made = CarBoard.makeStarterBoards(in: model)
        #expect(made.count == 2)
        #expect(model.settings.carBoardIDs == made.map(\.id))
        for board in made {
            #expect(!board.isHome)
            #expect(CarBoard.tiles(on: board).count == CarBoard.maximumTiles)
            #expect(CarBoard.tilesLeftOut(on: board) == 0)
        }
        #expect(model.layout(model.home) == before)
        #expect(model.store.boards().filter(\.isHome).count == 1)
    }

    @Test func yesAndNoAreInTheSameSpotsOnBothStarterBoards() throws {
        let model = makeModel()
        let made = CarBoard.makeStarterBoards(in: model)
        let spots = made.map { board in
            board.placedTiles.filter { ["Yes.", "No."].contains($0.spokenText) }
                .map { "\($0.spokenText)@\($0.row ?? -1),\($0.column ?? -1)" }.sorted()
        }
        #expect(spots[0].count == 2)
        #expect(spots[0] == spots[1])
    }

    @Test func theStarterBoardsAreOneUndoStep() throws {
        let model = makeModel()
        model.endEvent()
        let count = model.store.boards().count
        CarBoard.makeStarterBoards(in: model)
        model.endEvent()
        model.store.undo()
        #expect(model.store.boards().count == count)
    }

    @Test func theStarterPhrasesPassTheChecks() throws {
        let model = makeModel()
        let made = CarBoard.makeStarterBoards(in: model)
        // Only these boards' tiles: no praise or compliance phrases, every tile placed and speaking.
        let doc = ConfigBridge.export(boards: made).document
        let issues = HumValidator.semanticIssues(in: doc).filter { $0.path.contains("/tiles") }
        #expect(issues.isEmpty, "\(issues)")
    }

    @Test func carSettingsAreSavedOnThisDevice() throws {
        let defaults = UserDefaults(suiteName: "HumTests-\(UUID().uuidString)")!
        let ids = [UUID(), UUID()]
        let settings = DeviceSettings(defaults: defaults)
        settings.carBoardIDs = ids
        settings.carShowsEachPhrase = true
        settings.aboutMe = AboutMeCard(name: "Sam", lines: ["I'm autistic."], contactName: "Alex", contactPhone: "555 0100")
        let reloaded = DeviceSettings(defaults: defaults)
        #expect(reloaded.carBoardIDs == ids)
        #expect(reloaded.carShowsEachPhrase)
        #expect(reloaded.aboutMe == settings.aboutMe)
    }

    @Test func anEarlyBuildsSingleCarBoardIsKept() throws {
        let defaults = UserDefaults(suiteName: "HumTests-\(UUID().uuidString)")!
        let id = UUID()
        defaults.set(id.uuidString, forKey: "carPlay.board")
        #expect(DeviceSettings(defaults: defaults).carBoardIDs == [id])
    }
}

/// The About me card (CarPlay/AboutMeCard.swift).
@Suite("About me card")
struct AboutMeCardTests {
    @Test func emptyUntilSomethingIsFilledIn() {
        #expect(AboutMeCard().isEmpty)
        #expect(AboutMeCard(lines: ["  ", ""]).isEmpty)
        #expect(!AboutMeCard(contactPhone: "555").isEmpty)
    }

    @Test func readsTheNameLinesAndContact() {
        let card = AboutMeCard(name: "Sam", lines: ["I'm autistic", "", "Please give me time to answer."],
                               contactName: "Alex", contactPhone: "(555) 010-0")
        #expect(card.shownLines == ["I'm autistic", "Please give me time to answer."])
        #expect(card.contactText == "Alex · (555) 010-0")
        // A full stop after each line, and the number read digit by digit.
        #expect(card.spokenText == "My name is Sam. I'm autistic. Please give me time to answer. My emergency contact is Alex. Their number is 5 5 5 0 1 0 0.")
    }

    @Test func atMostSevenLines() {
        let card = AboutMeCard(lines: (1...9).map { "Line \($0)" })
        #expect(card.shownLines.count == AboutMeCard.maximumLines)
    }

    @Test func suggestionsHaveNoComplianceOrPraise() {
        let doc = HumDocument(boards: [HumBoard(id: UUID(), name: "Card", rows: 1, columns: AboutMeCard.suggestions.count, isHome: true,
                                                tiles: AboutMeCard.suggestions.enumerated().map { i, line in
                                                    HumTile(id: UUID(), label: "\(i)", spokenText: line, row: 0, column: i)
                                                })])
        let issues = HumValidator.semanticIssues(in: doc).filter { $0.path.contains("/tiles") }
        #expect(issues.isEmpty, "\(issues)")
    }
}

/// What the car's Show and Earlier use from history.
@MainActor
@Suite("Car history")
struct CarHistoryTests {
    @Test func recentSinceAConnection() {
        let history = SpeechHistory(fileURL: nil)
        let start = Date(timeIntervalSince1970: 1_000)
        history.add(label: "a", spokenText: "Before.", function: nil, colorHex: nil, at: start.addingTimeInterval(-60))
        history.add(label: "b", spokenText: "First.", function: nil, colorHex: nil, at: start.addingTimeInterval(5))
        history.add(label: "c", spokenText: "Second.", function: nil, colorHex: nil, at: start.addingTimeInterval(30))
        #expect(history.recent(10, since: start).map(\.spokenText) == ["Second.", "First."])
        #expect(history.recent(1, since: start).map(\.spokenText) == ["Second."])
    }

    @Test func historyKeepsTheTile() async throws {
        let model = makeModel()
        let board = model.store.createBoard(name: "Mine", rows: 1, columns: 1)
        let tile = try model.store.addTile(to: board, row: 0, column: 0, label: "hi", spokenText: "Hi there.")
        #expect(await model.say(tileID: tile.id))
        #expect(model.history.entries.last?.tileID == tile.id)
        model.say(phrase: "  My name is Sam.  ")
        #expect(model.history.entries.last?.spokenText == "My name is Sam.")
        #expect(model.history.entries.last?.tileID == nil)
    }
}
