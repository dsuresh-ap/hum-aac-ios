// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0
//
// Copies HumConfig's English word lists into the app's String Catalogs, so translators can translate them:
//   swift tools/update-word-catalogs.swift
// - EmojiKeywords.xcstrings: one string per emoji in EmojiSuggester (its search words).
// - PraisePhrases.xcstrings: one string per phrase in GLPRules.discouragedPhrases.
// Run it after changing either list. Translations already in the catalogs are kept; strings for emoji or
// phrases that are gone are removed. A unit test (ContentLanguageTests) fails when the catalogs are behind.

import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sources = root.appendingPathComponent("Packages/HumConfig/Sources/HumConfig")

func read(_ name: String) throws -> String {
    try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
}

func matches(_ pattern: String, in text: String) -> [[String]] {
    let regex = try! NSRegularExpression(pattern: pattern)
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
        (1..<match.numberOfRanges).map { String(text[Range(match.range(at: $0), in: text)!]) }
    }
}

/// Writes `english` (key → English value) into the catalog, keeping other languages' translations.
func update(_ catalog: String, _ english: [(key: String, value: String)], comment: (String) -> String) throws {
    let url = root.appendingPathComponent("hum-aac-ios/\(catalog).xcstrings")
    var strings: [String: Any] = [:]
    if let data = try? Data(contentsOf: url),
       let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
        strings = json["strings"] as? [String: Any] ?? [:]
    }
    var result: [String: Any] = [:]
    for (key, value) in english where result[key] == nil {
        var entry = strings[key] as? [String: Any] ?? [:]
        var localizations = entry["localizations"] as? [String: Any] ?? [:]
        localizations["en"] = ["stringUnit": ["state": "translated", "value": value]]
        entry["localizations"] = localizations
        entry["comment"] = comment(key)
        entry["extractionState"] = "manual"
        result[key] = entry
    }
    let removed = Set(strings.keys).subtracting(result.keys)
    let json: [String: Any] = ["sourceLanguage": "en", "strings": result, "version": "1.0"]
    var data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    data.append(Data("\n".utf8))
    try data.write(to: url)
    print("\(catalog): \(result.count) strings\(removed.isEmpty ? "" : ", removed \(removed.sorted())")")
}

/// "🧃" → "emoji_1F9C3": the catalog generates Swift names from its keys, and an emoji can't be one.
/// The app builds the same key (`ContentLanguage.emojiKey`).
func emojiKey(_ emoji: String) -> String {
    "emoji_" + emoji.unicodeScalars.map { String($0.value, radix: 16, uppercase: true) }.joined(separator: "_")
}
let emojiByKey = Dictionary(matches(#"e\("([^"]+)", "[^"]+"\)"#, in: try read("EmojiSuggester.swift")).map { (emojiKey($0[0]), $0[0]) },
                            uniquingKeysWith: { a, _ in a })
let emoji = matches(#"e\("([^"]+)", "([^"]+)"\)"#, in: try read("EmojiSuggester.swift")).map { (key: emojiKey($0[0]), value: $0[1]) }
try update("EmojiKeywords", emoji) { key in
    "Search words for the \(emojiByKey[key] ?? key) emoji in the tile picker, separated by commas. Use everyday words a parent would type, including words children use. Don't translate word for word if another word fits better."
}

let rules = try read("GLPRules.swift")
let list = rules[rules.range(of: "discouragedPhrases: [String] = [")!.upperBound...]
let phrases = matches(#""([^"]+)""#, in: String(list[..<list.range(of: "\n    ]")!.lowerBound])).map { (key: $0[0], value: $0[0]) }
try update("PraisePhrases", phrases) { _ in
    "A praise, reward or compliance phrase Hum warns about (tiles are the child's own voice, not a way to manage the child). Give the usual ways adults say it in your language, separated by commas. Lowercase, no punctuation."
}
