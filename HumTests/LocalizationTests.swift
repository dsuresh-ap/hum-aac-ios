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

/// The app ships translations; these load a few through the real bundle, plural rules included.
@Suite("Translations")
struct TranslationTests {
    nonisolated static let languages = ["de", "es", "fr", "it", "pt-BR", "zh-Hans"]

    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"), "\(language).lproj is missing")
        return try #require(Bundle(path: path))
    }

    @Test(arguments: languages)
    func everyLanguageShips(_ language: String) throws {
        let strings = try bundle(language)
        for table in ["Localizable", "EmojiKeywords", "PraisePhrases", "InfoPlist"] {
            #expect(strings.path(forResource: table, ofType: "strings") != nil, "\(language): \(table) is missing")
        }
        // A string every language translates, so it must not come back as the English key.
        #expect(strings.localizedString(forKey: "Grown-up settings", value: nil, table: nil) != "Grown-up settings")
    }

    @Test func pluralsFollowEachLanguage() throws {
        let german = try bundle("de").localizedString(forKey: "%lld tiles across", value: nil, table: nil)
        #expect(String.localizedStringWithFormat(german, 1) == "1 Feld pro Zeile")
        #expect(String.localizedStringWithFormat(german, 3) == "3 Felder pro Zeile")
        let chinese = try bundle("zh-Hans").localizedString(forKey: "%lld tiles across", value: nil, table: nil)
        #expect(String.localizedStringWithFormat(chinese, 3) == "每行 3 张卡片")
    }
}

/// What a parent reads when a file can't be imported: every problem HumConfig can find, in the app's words.
@Suite("Import problems in the app's words")
struct ImportProblemTextTests {
    let tile = ConfigSubject.tile("snack")
    let board = ConfigSubject.board("Food")

    var everyProblem: [ConfigProblem] {
        [.noWords(tile), .emptyLabel(tile), .noName(board), .missingID(tile), .invalidID(tile, field: "id"), .noPlace(tile),
         .noFormatVersion, .missingField(tile, field: "row"), .wrongType(tile, field: "row", expected: ["integer", "string"]),
         .notOneOf(tile, field: "function", options: ["protest", "request"]), .mustBe(.file, field: "formatVersion", value: "1"),
         .tooShort(tile, field: "label", min: 1), .tooLong(tile, field: "label", max: 60), .badColor(tile),
         .wrongFormat(tile, field: "image"), .outOfRange(board, field: "rows", min: "1", max: "20"),
         .tooFewItems(board, field: "tiles", min: 1), .tooManyItems(board, field: "tiles", max: 3), .notAllowed(.settings, field: "x"),
         .notAnObject, .unknownShape, .unsupportedVersion(9), .severalHomes(["Home", "Food"]), .duplicateBoardID(board),
         .boardTooSmall(board), .duplicateTileID(tile), .folderNeedsLabel(board: board),
         .outsideGrid(tile, board: board, row: 9, column: 1, rows: 2, columns: 2),
         .sameSpot(tile, otherTile: "park", row: 0, column: 1, board: board), .missingLink(tile), .creditWithoutPicture(tile),
         .praisePhrase(tile, phrase: "good job"), .missingMedia(tile: "dog", path: "media/dog.jpg"), .other("Something else.")]
    }

    @Test func everyProblemReadsAsASentence() {
        for problem in everyProblem {
            let text = problem.localizedText
            #expect(!text.isEmpty && !text.contains("%"), "\(problem)")
        }
        #expect(Set(everyProblem.map(\.localizedText)).count == everyProblem.count, "each problem has its own words")
        #expect(ConfigProblem.noWords(tile).localizedText == "Tile “snack” has no words to say.")
        #expect(ConfigProblem.wrongType(tile, field: "row", expected: ["integer", "string"]).localizedText
            == "Tile “snack”: “row” should be a whole number or text.")
        #expect(ConfigProblem.severalHomes(["Home", "Food"]).localizedText.contains("“Home” and “Food”"))
        #expect(ConfigProblem.outsideGrid(tile, board: board, row: 9, column: 1, rows: 2, columns: 2).localizedText.contains("row 9, column 1"))
    }

    @Test func everyKindOfSubjectIsNamed() {
        #expect(ConfigSubject.tileNumber(3, boardName: "Food", boardNumber: 2).localizedText == "Tile 3 on “Food”")
        #expect(ConfigSubject.tileNumber(3, boardName: nil, boardNumber: 2).localizedText == "Tile 3 on board 2")
        #expect(ConfigSubject.boardNumber(2).localizedText == "Board 2")
        #expect(ConfigSubject.settings.localizedText == "Settings")
        #expect(ConfigSubject.file.localizedText == "The file")
        let types = ["integer", "number", "string", "boolean", "array", "object"].map(ConfigProblem.localizedTypeName)
        #expect(Set(types).count == 6)
        #expect(ConfigProblem.localizedTypeName("date") == "date", "an unknown type stays as written")
    }

    @Test func everyErrorHasAMessage() {
        let issues = (1...7).map { ValidationIssue(.error, .noWords(.tile("t\($0)"))) } + [ValidationIssue(.warning, .missingLink(.tile("w")))]
        let invalid = HumConfigError.invalid(issues).localizedMessage
        #expect(invalid.hasPrefix("This file has some problems:\nTile “t1” has no words to say."))
        #expect(invalid.hasSuffix("…and 2 more."))
        #expect(!invalid.contains("“w”"), "warnings don't stop an import, so they aren't listed")

        let packages: [PackageProblem] = [.damaged, .noConfig, .unreadable, .tooBig]
        let texts = packages.map { HumConfigError.badPackage($0).localizedMessage }
        #expect(Set(texts).count == packages.count)
        #expect(texts.allSatisfy { $0.hasPrefix("This Hum file couldn't be opened. ") })
        #expect(!HumConfigError.notJSON.localizedMessage.isEmpty)
        #expect(HumConfigError.newerFormat(found: 2, supported: 1).localizedMessage.contains("newer version"))

        // Any error a parent might see gets readable words.
        #expect(friendlyMessage(for: HumConfigError.notJSON) == HumConfigError.notJSON.localizedMessage)
        #expect(friendlyMessage(for: StoreError.slotTaken) == StoreError.slotTaken.errorDescription)
        #expect(!friendlyMessage(for: CocoaError(.fileReadNoSuchFile)).isEmpty)
    }

    /// Every string in the app's catalog has all six translations, so a parent never meets English by
    /// surprise in their own language.
    @Test func everyStringIsTranslated() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("hum-aac-ios/Localizable.xcstrings"))
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        for (key, entry) in strings where !key.isEmpty && entry["shouldTranslate"] as? Bool != false {
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let missing = TranslationTests.languages.filter { localizations[$0] == nil }
            #expect(missing.isEmpty, "“\(key)” has no \(missing.joined(separator: ", "))")
        }
    }
}
