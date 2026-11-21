// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import HumConfig
@testable import Hum

/// The board CarPlay shows (CarPlay/CarBoard.swift): Home unless one is chosen, at most 8 speaking tiles,
/// in reading order. Choosing or making it never moves a tile.
@MainActor
@Suite("Car board")
struct CarBoardTests {
    @Test func homeUntilABoardIsChosen() throws {
        let model = makeModel()
        #expect(CarBoard.board(in: model)?.id == model.home.id)
        let other = model.store.createBoard(name: "Errands", rows: 2, columns: 2)
        model.settings.carBoardID = other.id
        #expect(CarBoard.board(in: model)?.id == other.id)
    }

    @Test func aDeletedCarBoardFallsBackToHome() throws {
        let model = makeModel()
        let other = model.store.createBoard(name: "Errands", rows: 2, columns: 2)
        model.settings.carBoardID = other.id
        try model.store.delete(other)
        #expect(CarBoard.board(in: model)?.id == model.home.id)
    }

    @Test func showsTheFirstEightSpeakingTilesInReadingOrder() throws {
        let model = makeModel()
        let board = model.store.createBoard(name: "Big", rows: 3, columns: 4)
        // Added out of order, so the order comes from the spots, not from when they were made.
        for spot in [(2, 3), (0, 1), (1, 0), (0, 0), (2, 0), (1, 2), (0, 3), (1, 1), (2, 2), (0, 2)] {
            try model.store.addTile(to: board, row: spot.0, column: spot.1, label: "\(spot.0)\(spot.1)", spokenText: "Tile \(spot.0)\(spot.1)")
        }
        let silent = try model.store.addTile(to: board, row: 1, column: 3, label: "folder", spokenText: "")
        silent.linkedBoardID = model.home.id
        let hidden = try #require(board.placedTiles.first { $0.label == "00" })
        model.store.setHidden(hidden, true)

        let shown = CarBoard.tiles(on: board).map(\.label)
        #expect(shown == ["01", "02", "03", "10", "11", "12", "20", "22"])
        #expect(CarBoard.tilesLeftOut(on: board) == 1)
    }

    @Test func aRecordedTileWithNoWordsStillShows() throws {
        let model = makeModel()
        let board = model.store.createBoard(name: "Mine", rows: 1, columns: 2)
        let recorded = try model.store.addTile(to: board, row: 0, column: 0, label: "mine", spokenText: "")
        recorded.audioData = Data([1, 2, 3])
        #expect(CarBoard.tiles(on: board).map(\.id) == [recorded.id])
    }

    @Test func theStarterBoardIsChosenAndLeavesOtherBoardsAlone() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let board = CarBoard.makeStarterBoard(in: model)
        #expect(model.settings.carBoardID == board.id)
        #expect(!board.isHome)
        #expect(CarBoard.tiles(on: board).count == CarBoard.maximumTiles)
        #expect(CarBoard.tilesLeftOut(on: board) == 0)
        #expect(model.layout(model.home) == before)
        #expect(model.store.boards().filter(\.isHome).count == 1)
    }

    @Test func theStarterBoardIsOneUndoStep() throws {
        let model = makeModel()
        model.endEvent()
        let count = model.store.boards().count
        CarBoard.makeStarterBoard(in: model)
        model.endEvent()
        model.store.undo()
        #expect(model.store.boards().count == count)
    }

    @Test func theStarterPhrasesPassTheChecks() throws {
        let model = makeModel()
        let board = CarBoard.makeStarterBoard(in: model)
        // Only this board's tiles: no praise or compliance phrases, every tile placed and speaking.
        let doc = ConfigBridge.export(boards: [board]).document
        let issues = HumValidator.semanticIssues(in: doc).filter { $0.path.hasPrefix("/boards/0/tiles") }
        #expect(issues.isEmpty, "\(issues)")
    }

    @Test func carBoardChoiceIsSavedOnThisDevice() throws {
        let defaults = UserDefaults(suiteName: "HumTests-\(UUID().uuidString)")!
        let id = UUID()
        DeviceSettings(defaults: defaults).carBoardID = id
        #expect(DeviceSettings(defaults: defaults).carBoardID == id)
    }
}
