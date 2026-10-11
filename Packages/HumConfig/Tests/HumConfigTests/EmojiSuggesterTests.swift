// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import HumConfig

@Suite("Emoji suggestions")
struct EmojiSuggesterTests {
    @Test(arguments: [
        ("juice", "Let's have juice!", "🧃"),
        ("all aboard", "All aboard!", "🚂"),
        ("stop", "Stop!", "✋"),
        ("all done", "All done", "✅"),
        ("ice cream", "I want ice cream", "🍦"),
        ("trains", "Trains go choo choo", "🚂"),
        ("swinging", "Let's go swinging!", "🔄"),
        ("bye-bye", "Bye-bye!", "👋"),
        ("to infinity", "To infinity and beyond!", "🚀"),
    ])
    func guessesFromWords(label: String, phrase: String, expected: String) {
        #expect(EmojiSuggester.suggestion(label: label, spokenText: phrase) == expected)
    }

    @Test func labelWordsWinOverPhraseWords() {
        // "dog" is in the label; "park" only in the phrase.
        #expect(EmojiSuggester.suggestions(label: "dog", spokenText: "Let's take the dog to the park").first == "🐶")
    }

    @Test func noMatchGivesNil() {
        #expect(EmojiSuggester.suggestion(label: "zzz", spokenText: "Qwerty blorp") == nil)
        #expect(EmojiSuggester.suggestion(label: "", spokenText: "") == nil)
    }

    @Test func suggestionsAreUniqueAndLimited() {
        let list = EmojiSuggester.suggestions(label: "hug", spokenText: "Hug me, I love hugs", limit: 3)
        #expect(list.count <= 3)
        #expect(Set(list).count == list.count)
    }

    @Test func searchMatchesKeywordPrefixes() {
        #expect(EmojiSuggester.search("din").contains("🦖"))
        #expect(EmojiSuggester.search("").isEmpty)
    }

    @Test func everyPickerEntryIsOneEmoji() {
        for entry in EmojiSuggester.categories.flatMap(\.entries) {
            #expect(EmojiSuggester.isSingleEmoji(entry.emoji), "\(entry.emoji) is not a single emoji")
            #expect(!entry.keywords.isEmpty)
        }
        #expect(!EmojiSuggester.isSingleEmoji("ab"))
        #expect(!EmojiSuggester.isSingleEmoji("1"))
        #expect(!EmojiSuggester.isSingleEmoji("🍎🍌"))
    }

    @Test func proposalsGetAPlaceholderEmoji() {
        let doc = HumDocument(boards: [HumBoard(name: "Home", rows: 2, columns: 2, isHome: true)])
        let result = ProposalChecker.check([
            .init(label: "apple", spokenText: "Let's have apple!"),
            .init(label: "x", spokenText: "Something odd", symbol: "not an emoji"),
            .init(label: "kept", spokenText: "Mine", symbol: "🦄"),
        ], parentPhrases: [], existing: doc)
        #expect(result.tiles.map(\.symbol) == ["🍎", nil, "🦄"])
        let built = ProposalChecker.document(from: result.tiles, targetBoardID: nil, existing: doc)
        #expect(built.boards.first?.tiles.first?.symbol == "🍎")
    }

    @Test func pastedLinesStayWhole() {
        let tiles = ProposalChecker.tiles(fromLines: "To infinity and beyond!\n\n  Let's get out of here!  \r\nAll done")
        #expect(tiles.map(\.spokenText) == ["To infinity and beyond!", "Let's get out of here!", "All done"])
        #expect(tiles.map(\.label) == ["To infinity and beyond", "Let's get out of", "All done"])
    }
}
