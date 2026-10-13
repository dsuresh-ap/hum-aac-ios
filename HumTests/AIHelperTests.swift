// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import HumConfig
@testable import Hum

/// The AI helper pipeline with a fake model: prompt → model output → GLP checks → tiles on the board.
/// The real model is only used by `liveOnDeviceModel`, which runs when HUM_LIVE_AI=1
/// (`TEST_RUNNER_HUM_LIVE_AI=1 xcodebuild test …`) on a device with Apple Intelligence.
@MainActor
@Suite("AI helper")
struct AIHelperTests {
    /// A fake model that returns canned tiles and remembers the prompts it was given.
    final class FakeModel {
        var replies: [Result<[ProposedTile], AIHelper.AIError>]
        var prompts: [String] = []
        var fallback = false

        init(_ replies: [Result<[ProposedTile], AIHelper.AIError>]) { self.replies = replies }

        var generator: AIHelper.Generator {
            { prompt, _ in
                self.prompts.append(prompt)
                let reply = self.replies.isEmpty ? .success([]) : self.replies.removeFirst()
                return AIHelper.Generation(tiles: try reply.get(), usedOnDeviceFallback: self.fallback)
            }
        }
    }

    func existing(_ model: AppModel) -> HumDocument { ConfigBridge.export(boards: model.store.boards()).document }

    @Test func promptHasTheRequestAndTileTextButNoMedia() throws {
        let model = makeModel()
        let snack = try #require(model.home.placedTiles.first { $0.label == "snack" })
        snack.imageData = Data(repeating: 7, count: 64)
        snack.audioData = Data(repeating: 9, count: 64)
        let prompt = AIHelper.prompts(for: .describe("She loves “all aboard!”"), existing: existing(model))
        #expect(prompt.parentPhrases == ["all aboard!"])
        #expect(prompt.full.contains("She loves “all aboard!”"))
        #expect(prompt.full.contains(snack.spokenText))
        #expect(!prompt.full.contains("media/"))
        #expect(prompt.short.contains("Some tiles already on the boards"))
    }

    @Test func praiseIsDroppedAndSplitGestaltsAreRejoined() async throws {
        let model = makeModel()
        let fake = FakeModel([.success([
            .init(label: "good job", spokenText: "Good job!"),
            .init(label: "infinity", spokenText: "To infinity", function: .comment),
            .init(label: "beyond", spokenText: "and beyond!", function: .comment),
        ])])
        let proposal = try await AIHelper.propose(.capture(phrases: ["To infinity and beyond!"], context: ""),
                                                  mode: .onDevice, existing: existing(model), generator: fake.generator)
        #expect(proposal.tiles.map(\.spokenText) == ["To infinity and beyond!"])
        #expect(proposal.notes.contains { $0.contains("Good job!") })
    }

    @Test func tilesAlreadyOnTheBoardAreNotSuggestedAgain() async throws {
        let model = makeModel()
        let phrase = try #require(model.home.placedTiles.first).spokenText
        let fake = FakeModel([.success([.init(label: "again", spokenText: phrase), .init(label: "train", spokenText: "All aboard!")])])
        let proposal = try await AIHelper.propose(.describe("trains"), mode: .onDevice, existing: existing(model), generator: fake.generator)
        #expect(proposal.tiles.map(\.spokenText) == ["All aboard!"])
    }

    @Test func suggestionsGetAnEmojiAndBadEmojiIsReplaced() async throws {
        let model = makeModel()
        let fake = FakeModel([.success([
            .init(label: "train", spokenText: "All aboard!", symbol: "a train"),
            .init(label: "rocket", spokenText: "Blast off!", symbol: "🛸"),
        ])])
        let proposal = try await AIHelper.propose(.describe("x"), mode: .onDevice, existing: existing(model), generator: fake.generator)
        #expect(proposal.tiles.map(\.symbol) == ["🚂", "🛸"])
    }

    @Test func tooLongRetriesWithTheShortPrompt() async throws {
        let model = makeModel()
        let fake = FakeModel([.failure(.contextTooLong), .success([.init(label: "train", spokenText: "All aboard!")])])
        let proposal = try await AIHelper.propose(.describe("trains"), mode: .onDevice, existing: existing(model), generator: fake.generator)
        #expect(fake.prompts.count == 2)
        #expect(fake.prompts[1].contains("Some tiles already on the boards"))
        #expect(proposal.tiles.count == 1)
    }

    @Test func otherErrorsReachTheParent() async throws {
        let model = makeModel()
        let fake = FakeModel([.failure(.quotaReached(resetDate: nil))])
        await #expect(throws: AIHelper.AIError.quotaReached(resetDate: nil)) {
            try await AIHelper.propose(.describe("trains"), mode: .privateCloud, existing: existing(model), generator: fake.generator)
        }
        #expect(AIHelper.AIError.quotaReached(resetDate: nil).errorDescription?.contains("On this device") == true)
    }

    @Test func cloudFallbackIsExplained() async throws {
        let model = makeModel()
        let fake = FakeModel([.success([.init(label: "train", spokenText: "All aboard!")])])
        fake.fallback = true
        let proposal = try await AIHelper.propose(.describe("trains"), mode: .privateCloud, existing: existing(model), generator: fake.generator)
        #expect(proposal.notes.first?.contains("on this device") == true)
    }

    @Test func protestOnASubBoardStaysThere() async throws {
        let model = makeModel()
        let fake = FakeModel([.success([.init(label: "no slide", spokenText: "No more slide!", function: .protest, boardName: "Park")])])
        let proposal = try await AIHelper.propose(.describe("park"), mode: .onDevice, existing: existing(model), generator: fake.generator)
        #expect(Set(proposal.tiles.compactMap(\.boardName)) == ["Park"])
    }

    /// Adding suggestions takes free spots, never moves a tile, and is one undo step.
    @Test func addingSuggestionsNeverMovesTiles() throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let tiles = [ProposedTile(label: "train", spokenText: "All aboard!", symbol: "🚂"),
                     ProposedTile(label: "rocket", spokenText: "Blast off!")]
        let summary = try ImportService(model: model).addSuggested(tiles, targetBoardID: model.home.id, source: "test")
        #expect(summary.movedTiles == 0)
        let after = model.layout(model.home)
        for (spot, label) in before { #expect(after[spot] == label) }
        let added = model.home.tiles?.filter { ["All aboard!", "Blast off!"].contains($0.spokenText) } ?? []
        #expect(added.count == 2)
        #expect(added.first { $0.label == "train" }?.symbol == "🚂")
        model.store.undo()
        #expect(model.layout(model.home) == before)
        #expect(model.home.tiles?.contains { $0.spokenText == "All aboard!" } == false)

        // Redo adds them again without moving anything, and undo still works (BUGS.md, HUM-052).
        model.store.undoManager?.redo()
        #expect(model.home.tiles?.filter { ["All aboard!", "Blast off!"].contains($0.spokenText) }.count == 2)
        for (spot, label) in before { #expect(model.layout(model.home)[spot] == label) }
        model.store.undo()
        #expect(model.layout(model.home) == before)
    }

    @Test func availabilityNeverCrashes() {
        for mode in AIHelper.Mode.allCases {
            if case .unavailable(let reason) = AIHelper.availability(mode: mode) { #expect(!reason.isEmpty) }
        }
    }

    /// The real on-device model. Slow and needs Apple Intelligence, so it only runs when asked.
    @Test(.enabled {
              guard ProcessInfo.processInfo.environment["HUM_LIVE_AI"] == "1" else { return false }
              return await MainActor.run { AIHelper.availability(mode: .onDevice) == .available }
          },
          .timeLimit(.minutes(2)))
    func liveOnDeviceModel() async throws {
        let model = makeModel()
        let proposal = try await AIHelper.propose(
            .capture(phrases: ["To infinity and beyond!", "Let's get out of here!"], context: "at the park"),
            mode: .onDevice, existing: existing(model))
        #expect(!proposal.tiles.isEmpty)
        for tile in proposal.tiles {
            #expect(GLPRules.discouragedPhrase(in: tile.spokenText) == nil)
            #expect(!tile.label.isEmpty && tile.label.split(separator: " ").count <= ProposalChecker.maxLabelWords)
        }
        // Gestalts the parent gave come back whole, never as fragments.
        #expect(!proposal.tiles.contains { $0.spokenText.lowercased() == "to infinity" })
    }
}
