// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import HumConfig
import SwiftData

/// Hum's built-in starter board (`starter.hum.json`), so sync can tell it apart from a family's own Home.
///
/// A language can have its own starter, `starter.<language>.hum.json` (e.g. `starter.es.hum.json` or
/// `starter.pt-BR.hum.json`) next to the English one. It must be the same board with the same tile IDs,
/// spots, functions and folders; only the words (and the emoji, if needed) change. A test checks this,
/// and docs/LOCALIZATION.md explains how to make one.
@MainActor
enum StarterBoard {
    /// The starter in the language Hum's screens are shown in, so the starter's words match the rest of the
    /// app (and the first-run card that quotes them). English when that language has no starter of its own.
    static var url: URL? { url(for: Bundle.main.preferredLocalizations, in: .main) }

    static func url(for languages: [String], in bundle: Bundle) -> URL? {
        let available = Set(variantURLs(in: bundle).keys)
        if let language = pick(languages, available: available) {
            return bundle.url(forResource: "starter.\(language).hum", withExtension: "json")
        }
        return bundle.url(forResource: "starter.hum", withExtension: "json")
    }

    /// The first of `languages` (BCP 47, like "pt-BR") that has a starter of its own: the full
    /// identifier first, then just the language. Nil means the English starter.
    nonisolated static func pick(_ languages: [String], available: Set<String>) -> String? {
        for identifier in languages {
            let full = identifier.replacingOccurrences(of: "_", with: "-")
            if available.contains(full) { return full }
            if let base = full.split(separator: "-").first.map(String.init), available.contains(base) { return base }
            // English is the base file; an English device never takes another language's starter.
            if full.hasPrefix("en") { return nil }
        }
        return nil
    }

    /// Every language's own starter in the bundle, keyed by language ("es", "pt-BR").
    static func variantURLs(in bundle: Bundle) -> [String: URL] {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        var result: [String: URL] = [:]
        for url in urls {
            let name = url.lastPathComponent
            guard name.hasPrefix("starter."), name.hasSuffix(".hum.json"), name != "starter.hum.json" else { continue }
            result[String(name.dropFirst("starter.".count).dropLast(".hum.json".count))] = url
        }
        return result
    }

    /// The starter's bundled document (in Hum's language), or nil if the file is missing.
    static let document: HumDocument? = url.flatMap(load)

    /// Every bundled starter, English first. A device in another language may have made the starter Home.
    static let allDocuments: [HumDocument] = {
        let base = Bundle.main.url(forResource: "starter.hum", withExtension: "json")
        return ([base].compactMap { $0 } + variantURLs(in: .main).values.sorted { $0.path < $1.path }).compactMap(load)
    }()

    nonisolated static func load(_ url: URL) -> HumDocument? {
        (try? Data(contentsOf: url)).flatMap { try? HumConfigLoader.load($0).document }
    }

    /// The starter Home's fixed id (the same on every device).
    static var homeID: UUID? { document?.homeBoard?.id }

    /// True if `board` is the starter Home exactly as Hum made it, in any language: same size, the same tiles
    /// in the same spots with the same words, and no photos or recordings added. Such a board has no family
    /// work in it.
    static func isUntouched(_ board: Board) -> Bool {
        allDocuments.compactMap(\.homeBoard).contains { isUntouched(board, starter: $0) }
    }

    private static func isUntouched(_ board: Board, starter: HumBoard) -> Bool {
        guard board.id == starter.id,
              board.rows == starter.rows, board.columns == starter.columns else { return false }
        let tiles = (board.tiles ?? []).filter { !$0.isDeleted }
        guard tiles.count == starter.tiles.count else { return false }
        let expected = Dictionary(uniqueKeysWithValues: starter.tiles.map { ($0.id, $0) })
        return tiles.allSatisfy { tile in
            guard let original = expected[tile.id] else { return false }
            return tile.label == original.label && tile.spokenText == original.spokenText
                && tile.row == original.row && tile.column == original.column
                && tile.linkedBoardID == original.linkedBoardID && tile.isHidden == original.hidden
                && tile.imageData == nil && tile.audioData == nil
        }
    }
}
