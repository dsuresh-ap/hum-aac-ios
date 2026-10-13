// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Rules that keep Hum neurodiversity-affirming and right for Gestalt Language Processors.
///
/// They live in HumConfig (not the app) so the same checks run in the app, in the `hum-config` CLI,
/// on AI output, and in CI.
public enum GLPRules {
    /// Praise, reward and compliance phrases. Hum is non-behavioral: a tile is the child's voice,
    /// not a tool to manage the child. These are flagged in files and removed from AI proposals.
    public static let discouragedPhrases: [String] = [
        // praise / reward
        "good job", "great job", "good girl", "good boy", "well done", "nice work", "good work",
        "you earned", "earn a", "sticker chart", "token", "reward", "high five for",
        // compliance
        "quiet hands", "hands down", "look at me", "eyes on me", "sit nicely", "be good",
        "use your words", "say please", "calm body", "nice hands", "first work",
    ]

    /// Lowercases, folds curly quotes and strips punctuation so phrase matching is forgiving.
    public static func normalize(_ text: String) -> String {
        let folded = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        let kept = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) || scalar == "'"
                ? Character(scalar) : " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Returns the discouraged phrase found in `text`, if any. Matches whole words only.
    public static func discouragedPhrase(in text: String) -> String? {
        let padded = " " + normalize(text) + " "
        return discouragedPhrases.first { padded.contains(" " + $0 + " ") }
    }

    /// True if `text` is a smaller piece of `gestalt` (a run of its words, but not the whole thing).
    /// Used to catch AI output that split one gestalt into several tiles.
    public static func isFragment(_ text: String, of gestalt: String) -> Bool {
        let part = normalize(text).split(separator: " ")
        let whole = normalize(gestalt).split(separator: " ")
        guard !part.isEmpty, part.count < whole.count else { return false }
        for start in 0...(whole.count - part.count) where Array(whole[start..<(start + part.count)]) == part {
            return true
        }
        return false
    }
}
