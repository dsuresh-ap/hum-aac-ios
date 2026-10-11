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
        #expect(doc.boards.map(\.name) == ["Trains"])
    }
}
