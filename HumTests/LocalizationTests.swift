// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import HumConfig
@testable import Hum

/// Text with counts comes from the String Catalog's plural rules, not from `n == 1 ? "" : "s"` in code.
/// These check the English rules (tests run in English).
@MainActor
@Suite("Localization")
struct LocalizationTests {
    @Test func importSummaryUsesPluralRules() {
        var summary = MergePlanner.Summary()
        summary.newTiles = 1
        #expect(summary.localizedSentence == "1 new tile, 0 changed tiles, 0 removed. No tiles will move.")
        summary.newTiles = 3
        summary.newBoards = 1
        summary.movedTiles = 1
        summary.unplacedTiles = 2
        #expect(summary.localizedSentence == "1 new folder, 3 new tiles, 0 changed tiles, 0 removed. 1 tile will move. 2 new tiles will need a spot. You can place them in edit mode.")
    }

    @Test func importBannerUsesPluralRules() {
        var summary = MergePlanner.Summary()
        summary.newTiles = 1
        summary.unplacedTiles = 1
        let one = ImportReport(fileName: "Trains.hum", summary: summary, mode: .merge)
        #expect(one.message == "Added 1 tile. 1 tile waits below the board for a spot.")

        summary.newTiles = 4
        summary.newBoards = 3
        summary.unplacedTiles = 0
        summary.homeFolderName = "Trains"
        let folders = ImportReport(fileName: "Trains.hum", summary: summary, mode: .merge)
        #expect(folders.message == "Added “Trains.hum” as a folder called “Trains” on Home, with 2 more folders inside.")

        summary.homeFolderName = nil
        let newFolder = ImportReport(fileName: "Trains.hum", summary: summary, mode: .merge, folderName: "Trains")
        #expect(newFolder.message == "Added 4 tiles and a new folder, “Trains”.")
    }

    @Test func checkerNotesAreTranslatable() {
        #expect(ProposalNote.alreadyOnBoards(phrase: "Hi!").localizedText == "“Hi!” is already on your boards.")
        #expect(ProposalNote.keptWhole(phrase: "to infinity and beyond!").localizedText == ProposalNote.keptWhole(phrase: "to infinity and beyond!").text)
    }
}

/// A language can have its own starter board. It must be the same board, so a child's motor plan and
/// iCloud sync (which looks for the untouched starter by its IDs) work the same in every language.
@MainActor
@Suite("Starter board languages")
struct StarterLanguageTests {
    @Test func picksTheClosestLanguage() {
        #expect(StarterBoard.pick(["pt-BR"], available: ["pt"]) == "pt")
        #expect(StarterBoard.pick(["pt-BR"], available: ["pt", "pt-BR"]) == "pt-BR")
        #expect(StarterBoard.pick(["pt_BR"], available: ["pt-BR"]) == "pt-BR")
        #expect(StarterBoard.pick(["de"], available: ["es"]) == nil)
        #expect(StarterBoard.pick(["en-GB", "es"], available: ["es"]) == nil, "English uses the English starter")
        #expect(StarterBoard.pick([], available: ["es"]) == nil)
    }

    @Test func everyLanguageHasTheSameBoard() throws {
        let baseURL = try #require(Bundle.main.url(forResource: "starter.hum", withExtension: "json"))
        let base = try #require(StarterBoard.load(baseURL))
        for (language, url) in StarterBoard.variantURLs(in: .main) {
            let variant = try #require(StarterBoard.load(url), "starter.\(language).hum.json doesn't load")
            #expect(variant.boards.count == base.boards.count, "\(language): same boards")
            for (a, b) in zip(base.boards, variant.boards) {
                #expect(a.id == b.id && a.rows == b.rows && a.columns == b.columns && a.isHome == b.isHome,
                        "\(language): board \(a.name) keeps its ID and size")
                #expect(a.tiles.map(\.id) == b.tiles.map(\.id), "\(language): same tiles, same order")
                for (x, y) in zip(a.tiles, b.tiles) {
                    #expect(x.row == y.row && x.column == y.column && x.function == y.function
                            && x.linkedBoardID == y.linkedBoardID && x.hidden == y.hidden,
                            "\(language): tile \(x.label) keeps its spot, function and folder")
                    #expect(!y.spokenText.isEmpty, "\(language): tile \(x.label) has words")
                }
            }
        }
    }
}

@Suite("Translated word lists")
struct ContentLanguageTests {
    @Test func translatedListsAreSplitIntoWords() {
        #expect(ContentLanguage.words("zumo, jugo ,", key: "🧃") == ["zumo", "jugo"])
        #expect(ContentLanguage.words("good job", key: "good job").isEmpty, "No translation: nothing to add")
    }

    /// Every emoji and praise phrase in HumConfig is in the app's catalogs, so translators see them all.
    @Test func catalogsCoverHumConfigsLists() throws {
        func keys(_ name: String) throws -> Set<String> {
            let data = try Data(contentsOf: repoRoot.appendingPathComponent("hum-aac-ios/\(name).xcstrings"))
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return Set((try #require(json["strings"] as? [String: Any])).keys)
        }
        #expect(ContentLanguage.emojiKey("🧃") == "emoji_1F9C3")
        let emoji = Set(EmojiSuggester.categories.flatMap(\.entries).map { ContentLanguage.emojiKey($0.emoji) })
        #expect(emoji.subtracting(try keys("EmojiKeywords")).isEmpty, "Run the generator in docs/LOCALIZATION.md")
        #expect(Set(GLPRules.discouragedPhrases).subtracting(try keys("PraisePhrases")).isEmpty, "Run the generator in docs/LOCALIZATION.md")
    }
}
