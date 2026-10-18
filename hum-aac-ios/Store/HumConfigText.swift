// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import HumConfig

// HumConfig's words, in the app's language. HumConfig itself keeps English text (it also runs on Linux and
// in the hum-config tool, without the app's String Catalog), so every sentence a parent sees is built here.

/// The text to show a parent for any error: HumConfig's in the app's language, then the error's own.
nonisolated func friendlyMessage(for error: Error) -> String {
    if let config = error as? HumConfigError { return config.localizedMessage }
    return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}

/// HumConfig's word lists are English. This adds the translated ones from EmojiKeywords.xcstrings (emoji
/// search words) and PraisePhrases.xcstrings (phrases Hum warns about), so search, emoji suggestions and the
/// praise check work in Hum's language too. Runs once at launch; does nothing while Hum is in English.
enum ContentLanguage {
    static func install(bundle: Bundle = .main) {
        guard let language = bundle.preferredLocalizations.first, !language.hasPrefix("en") else { return }
        var keywords: [String: [String]] = [:]
        for entry in EmojiSuggester.categories.flatMap(\.entries) {
            let key = emojiKey(entry.emoji)
            keywords[entry.emoji, default: []] += words(bundle.localizedString(forKey: key, value: "", table: "EmojiKeywords"), key: key)
        }
        EmojiSuggester.addKeywords(keywords)
        GLPRules.addDiscouragedPhrases(GLPRules.discouragedPhrases.flatMap {
            words(bundle.localizedString(forKey: $0, value: "", table: "PraisePhrases"), key: $0)
        })
    }

    /// "🧃" → "emoji_1F9C3", the emoji's key in EmojiKeywords.xcstrings (tools/update-word-catalogs.swift
    /// makes the same keys).
    nonisolated static func emojiKey(_ emoji: String) -> String {
        "emoji_" + emoji.unicodeScalars.map { String($0.value, radix: 16, uppercase: true) }.joined(separator: "_")
    }

    /// "zumo, jugo" → ["zumo", "jugo"]. A missing translation comes back as the key itself: nothing to add.
    nonisolated static func words(_ text: String, key: String) -> [String] {
        guard text != key else { return [] }
        return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

extension HumConfigError {
    nonisolated var localizedMessage: String {
        switch self {
        case .notJSON:
            return String(localized: "This isn't a Hum file. Hum opens .hum files and hum.json files.", comment: "Why a Hum file couldn't be imported.")
        case .newerFormat:
            return String(localized: "This file was made with a newer version of Hum. Update Hum to open it.", comment: "Why a Hum file couldn't be imported.")
        case .invalid(let issues):
            let errors = issues.filter { $0.severity == .error }.map(\.localizedMessage)
            var text = String(localized: "This file has some problems:", comment: "Why a Hum file couldn't be imported.") + "\n" + errors.prefix(5).joined(separator: "\n")
            if errors.count > 5 { text += "\n" + String(localized: "…and \(errors.count - 5) more.", comment: "Why a Hum file couldn't be imported.") }
            return text
        case .badPackage(let reason):
            return String(localized: "This Hum file couldn't be opened. \(reason.localizedText)", comment: "Why a Hum file couldn't be imported.")
        }
    }
}

extension PackageProblem {
    nonisolated var localizedText: String {
        switch self {
        case .damaged: String(localized: "It may be damaged, or only partly downloaded.", comment: "Why a Hum file couldn't be imported.")
        case .noConfig: String(localized: "There are no boards inside it.", comment: "Why a Hum file couldn't be imported.")
        case .unreadable: String(localized: "Try saving or downloading it again.", comment: "Why a Hum file couldn't be imported.")
        case .tooBig: String(localized: "It's too big for Hum to open.", comment: "Why a Hum file couldn't be imported.")
        }
    }
}

extension ValidationIssue {
    /// The issue as a sentence in the app's language.
    nonisolated var localizedMessage: String { problem.localizedText }
}

extension ConfigSubject {
    /// "Tile “snack”", "Board 2", …: the start of a sentence about a file problem.
    nonisolated var localizedText: String {
        switch self {
        case .tile(let name): String(localized: "Tile “\(name)”", comment: "Starts a sentence about a problem in a Hum file.")
        case .tileNumber(let n, let boardName?, _):
            String(localized: "Tile \(n) on “\(boardName)”", comment: "Starts a sentence about a problem in a Hum file.")
        case .tileNumber(let n, nil, let boardNumber):
            String(localized: "Tile \(n) on board \(boardNumber)", comment: "Starts a sentence about a problem in a Hum file.")
        case .board(let name): String(localized: "Board “\(name)”", comment: "Starts a sentence about a problem in a Hum file.")
        case .boardNumber(let n): String(localized: "Board \(n)", comment: "Starts a sentence about a problem in a Hum file.")
        case .settings: String(localized: "Settings", comment: "Starts a sentence about a problem in a Hum file's settings.")
        case .file: String(localized: "The file", comment: "Starts a sentence about a problem in a Hum file.")
        }
    }
}

extension ConfigProblem {
    /// The problem in the app's language. Field names ("spokenText") stay as they are written in the file.
    nonisolated var localizedText: String {
        switch self {
        case .noWords(let s): return String(localized: "\(s.localizedText) has no words to say.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .emptyLabel(let s): return String(localized: "\(s.localizedText) has an empty label.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .noName(let s): return String(localized: "\(s.localizedText) has no name.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .missingID(let s): return String(localized: "\(s.localizedText) is missing its ID. Every board and tile needs its own ID.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .invalidID(let s, let field):
            return String(localized: "\(s.localizedText): “\(field)” isn't a valid ID. It should look like 3F2504E0-4F89-11D3-9A0C-0305E82C3301.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .noPlace(let s): return String(localized: "\(s.localizedText) has no spot on the board (it needs both “row” and “column”).", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .noFormatVersion: return String(localized: "The file is missing “formatVersion”. Add \"formatVersion\": 1 at the top.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .missingField(let s, let field): return String(localized: "\(s.localizedText) is missing “\(field)”.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .wrongType(let s, let field, let expected):
            let types = expected.map(Self.localizedTypeName).formatted(.list(type: .or))
            return String(localized: "\(s.localizedText): “\(field)” should be \(types).", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .notOneOf(let s, let field, let options):
            return String(localized: "\(s.localizedText): “\(field)” must be one of: \(options.joined(separator: ", ")).")
        case .mustBe(let s, let field, let value): return String(localized: "\(s.localizedText): “\(field)” must be \(value).", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .tooShort(let s, let field, let n):
            return String(localized: "\(s.localizedText): “\(field)” must have at least \(n) characters.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .tooLong(let s, let field, let n):
            return String(localized: "\(s.localizedText): “\(field)” is too long (at most \(n) characters).", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .badColor(let s): return String(localized: "\(s.localizedText): “color” should look like #A1B2C3.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .wrongFormat(let s, let field): return String(localized: "\(s.localizedText): “\(field)” has the wrong format.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .outOfRange(let s, let field, let lo, let hi):
            return String(localized: "\(s.localizedText): “\(field)” must be between \(lo) and \(hi).", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .tooFewItems(let s, let field, let n):
            return String(localized: "\(s.localizedText): “\(field)” needs at least \(n) items.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .tooManyItems(let s, let field, let n):
            return String(localized: "\(s.localizedText): “\(field)” can have at most \(n) items.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .notAllowed(let s, let field): return String(localized: "\(s.localizedText): “\(field)” doesn't belong here.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .notAnObject:
            return String(localized: "This isn't a Hum file. It should start with { and contain \"formatVersion\" and \"boards\".", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .unknownShape: return String(localized: "Hum doesn't understand how this file is laid out.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .unsupportedVersion(let v): return String(localized: "Format version \(v) isn't supported.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .severalHomes(let names):
            let list = names.map { String(localized: "“\($0)”", comment: "Words in quotes.") }.formatted(.list(type: .and))
            return String(localized: "More than one board is marked as Home (\(list)). Only one can be Home.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .duplicateBoardID(let s):
            return String(localized: "\(s.localizedText) has the same ID as another board. Every board needs its own ID.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .boardTooSmall(let s): return String(localized: "\(s.localizedText) is too small. A board needs at least 2 spots.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .duplicateTileID(let s):
            return String(localized: "\(s.localizedText) has the same ID as another tile. Every tile needs its own ID.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .folderNeedsLabel(let board):
            return String(localized: "A folder tile on \(board.localizedText) needs a label or words to say.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .outsideGrid(let s, let board, let row, let column, let rows, let columns):
            return String(localized: "\(s.localizedText) is outside \(board.localizedText): it's at row \(row), column \(column), but the board has \(rows) rows and \(columns) columns (counting from 0).", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .sameSpot(let s, let other, let row, let column, let board):
            return String(localized: "\(s.localizedText) and tile “\(other)” are in the same spot (row \(row), column \(column)) on \(board.localizedText).", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .missingLink(let s):
            return String(localized: "\(s.localizedText) opens a board that isn't in this file. It still speaks; it will open the board once that board is added.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .creditWithoutPicture(let s):
            return String(localized: "\(s.localizedText) has a picture credit but no picture. The credit is kept anyway.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .praisePhrase(let s, let phrase):
            return String(localized: "\(s.localizedText) says “\(phrase)”. Hum leaves out praise, reward and instruction phrases, because tiles are your child's own voice.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .missingMedia(let tile, let path):
            return String(localized: "Tile “\(tile)” needs “\(path)”, which isn't in the file. The tile still works without it.", comment: "A problem found in a Hum file. The first value is the board or tile it is about (like Tile “snack”). Words in “ ” such as “spokenText” are names from the file: keep them as they are.")
        case .other(let text): return text
        }
    }

    nonisolated static func localizedTypeName(_ type: String) -> String {
        switch type {
        case "integer": String(localized: "a whole number", comment: "What a value in a Hum file should be.")
        case "number": String(localized: "a number", comment: "What a value in a Hum file should be.")
        case "string": String(localized: "text", comment: "What a value in a Hum file should be.")
        case "boolean": String(localized: "true or false", comment: "What a value in a Hum file should be.")
        case "array": String(localized: "a list", comment: "What a value in a Hum file should be.")
        case "object": String(localized: "a group of values", comment: "What a value in a Hum file should be (a JSON object).")
        default: type
        }
    }
}

extension EmojiSuggester.Category {
    /// The category's heading in the app's language. HumConfig keeps the English names (it also runs
    /// on Linux, without the app's String Catalog).
    nonisolated var localizedName: String {
        switch name {
        case "Feelings & me": String(localized: "Feelings & me", comment: "Emoji picker heading.")
        case "Yes, no & help": String(localized: "Yes, no & help", comment: "Emoji picker heading.")
        case "Food & drink": String(localized: "Food & drink", comment: "Emoji picker heading.")
        case "Play & things": String(localized: "Play & things", comment: "Emoji picker heading.")
        case "Places & outside": String(localized: "Places & outside", comment: "Emoji picker heading.")
        case "Animals": String(localized: "Animals", comment: "Emoji picker heading.")
        case "Body & care": String(localized: "Body & care", comment: "Emoji picker heading.")
        case "People": String(localized: "People", comment: "Emoji picker heading.")
        default: name
        }
    }
}

extension MergePlanner.Summary {
    /// The preview's sentence in the app's language, e.g. "3 new tiles, 2 changed tiles, 0 removed. No tiles
    /// will move." HumConfig's `sentence` stays English for the command-line tool.
    nonisolated var localizedSentence: String {
        var parts: [String] = []
        if newBoards > 0 { parts.append(String(localized: "\(newBoards) new folders")) }
        parts.append(String(localized: "\(newTiles) new tiles"))
        parts.append(String(localized: "\(changedTiles) changed tiles"))
        parts.append(String(localized: "\(removedTiles) removed", comment: "How many tiles an import removes."))
        var text = String(localized: "\(parts.formatted(.list(type: .and, width: .narrow))).", comment: "The import counts, as a sentence.")
        text += " " + (movedTiles == 0 ? String(localized: "No tiles will move.") : String(localized: "\(movedTiles) tiles will move."))
        if let homeFolderName {
            text += " " + String(localized: "The file's Home becomes a folder called “\(homeFolderName)” on your Home.")
        }
        if unplacedTiles > 0 {
            text += " " + String(localized: "\(unplacedTiles) new tiles will need a spot. You can place them in edit mode.")
        }
        return text
    }
}

extension ProposalNote {
    /// The note in the app's language (HumConfig's `text` is English).
    nonisolated var localizedText: String {
        switch self {
        case .leftOutPraise(let phrase, let word):
            String(localized: "Left out “\(phrase)” because “\(word)” is praise or an instruction, not your child's own words.")
        case .keptWhole(let phrase): String(localized: "Kept “\(phrase)” whole instead of splitting it.")
        case .alreadyOnBoards(let phrase): String(localized: "“\(phrase)” is already on your boards.")
        }
    }
}
