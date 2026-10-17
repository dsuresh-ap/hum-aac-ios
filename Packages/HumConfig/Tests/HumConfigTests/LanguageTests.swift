// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import HumConfig

/// HumConfig's word lists are English. The app adds its translated words at launch; these check that the
/// added words work everywhere the English ones do. (The words added here stay for the rest of the run,
/// so they are ones no other test uses.)
@Suite("Other languages")
struct LanguageTests {
    @Test func addedEmojiWordsAreSearchedAndSuggested() {
        EmojiSuggester.addKeywords(["🧃": ["Zumito"], "🛸": ["zzqq"]])
        #expect(EmojiSuggester.search("zumi") == ["🧃"])
        #expect(EmojiSuggester.suggestion(label: "", spokenText: "Quiero zumito") == "🧃")
        #expect(EmojiSuggester.search("juice").contains("🧃"), "English still works")
        #expect(EmojiSuggester.search("zzqq").isEmpty, "Emoji outside the set are ignored")
    }

    @Test func addedPraisePhrasesAreFlaggedAndLeftOut() {
        GLPRules.addDiscouragedPhrases(["¡Muy bien hecho!"])
        #expect(GLPRules.discouragedPhrase(in: "Muy bien hecho, campeón") == "muy bien hecho")
        #expect(GLPRules.discouragedPhrase(in: "good job") == "good job")
        let result = ProposalChecker.check([ProposedTile(label: "bien", spokenText: "Muy bien hecho")], parentPhrases: [],
                                           existing: HumDocument(boards: []))
        #expect(result.tiles.isEmpty)
    }

    @Test func problemsKeepTheirEnglishSentence() {
        let issue = ValidationIssue(.error, .noWords(.tile("snack")))
        #expect(issue.message == "Tile 'snack' has no words to say.")
        #expect(ValidationIssue(.warning, "Plain text").problem == .other("Plain text"))
        #expect(HumConfigError.badPackage(.noConfig).errorDescription == "This .hum file couldn't be opened. It has no hum.json inside.")
    }
}
