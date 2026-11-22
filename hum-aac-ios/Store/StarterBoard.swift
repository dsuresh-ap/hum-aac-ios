// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import HumConfig
import SwiftData

/// Hum's built-in starter boards (`starter.hum`), so sync can tell them apart from a family's own boards.
///
/// The starter is a `.hum` package: a Home with folders for daily routines, and an ARASAAC picture on every
/// tile. Its source is `examples/starter/` (`hum-config pack examples/starter hum-aac-ios/Resources/starter.hum`).
///
/// A language can have its own starter, `starter.<language>.hum` (e.g. `starter.es.hum` or `starter.pt-BR.hum`)
/// next to the English one. It must be the same boards with the same tile IDs, spots, functions, folders and
/// pictures; only the words (and the emoji, if needed) change. A test checks this, and docs/LOCALIZATION.md
/// explains how to make one.
///
/// Hum 1.0 shipped a different starter (`starter-1.0.hum.json`, one Home board). It stays in the app so a
/// device that made it is still recognized when it joins sync.
@MainActor
enum StarterBoard {
    /// The starter in the language Hum's screens are shown in, so the starter's words match the rest of the
    /// app. English when that language has no starter of its own.
    static var url: URL? { url(for: Bundle.main.preferredLocalizations, in: .main) }

    /// Hum 1.0's starter. Tests also use it as sample data, because many were written around its tiles.
    static var legacyURL: URL? { Bundle.main.url(forResource: "starter-1.0.hum", withExtension: "json") }

    static func url(for languages: [String], in bundle: Bundle) -> URL? {
        let available = Set(variantURLs(in: bundle).keys)
        if let language = pick(languages, available: available) {
            return bundle.url(forResource: "starter.\(language)", withExtension: "hum")
        }
        return bundle.url(forResource: "starter", withExtension: "hum")
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
        let urls = bundle.urls(forResourcesWithExtension: "hum", subdirectory: nil) ?? []
        var result: [String: URL] = [:]
        for url in urls {
            let name = url.lastPathComponent
            guard name.hasPrefix("starter."), name.hasSuffix(".hum"), name != "starter.hum" else { continue }
            result[String(name.dropFirst("starter.".count).dropLast(".hum".count))] = url
        }
        return result
    }

    /// The starter's bundled document (in Hum's language), or nil if the file is missing.
    static let document: HumDocument? = url.flatMap(load)?.document

    /// Every starter a device may have made, English first, then other languages, then Hum 1.0's.
    private static let allStarters: [LoadedConfig] = {
        let base = Bundle.main.url(forResource: "starter", withExtension: "hum")
        let variants = variantURLs(in: .main).values.sorted { $0.path < $1.path }
        return ([base].compactMap { $0 } + variants + [legacyURL].compactMap { $0 }).compactMap(load)
    }()

    static var allDocuments: [HumDocument] { allStarters.map(\.document) }

    nonisolated static func load(_ url: URL) -> LoadedConfig? {
        (try? Data(contentsOf: url)).flatMap { try? HumConfigLoader.load($0) }
    }

    /// The starter Home's fixed id (the same on every device).
    static var homeID: UUID? { document?.homeBoard?.id }

    /// The Home ids of every starter, Hum 1.0's included.
    static var homeIDs: Set<UUID> { Set(allDocuments.compactMap(\.homeBoard?.id)) }

    /// True if `board` is one of the starter's boards exactly as Hum made it, in any language: same size, the
    /// same tiles in the same spots with the same words and pictures, and no recordings. Such a board has no
    /// family work in it.
    static func isUntouched(_ board: Board) -> Bool {
        allStarters.contains { starter in
            starter.document.boards.contains { $0.id == board.id && isUntouched(board, starter: $0, media: starter.media) }
        }
    }

    private static func isUntouched(_ board: Board, starter: HumBoard, media: [String: Data]) -> Bool {
        guard board.rows == starter.rows, board.columns == starter.columns else { return false }
        let tiles = (board.tiles ?? []).filter { !$0.isDeleted }
        guard tiles.count == starter.tiles.count else { return false }
        let expected = Dictionary(uniqueKeysWithValues: starter.tiles.map { ($0.id, $0) })
        return tiles.allSatisfy { tile in
            guard let original = expected[tile.id] else { return false }
            return tile.label == original.label && tile.spokenText == original.spokenText
                && tile.row == original.row && tile.column == original.column
                && tile.linkedBoardID == original.linkedBoardID && tile.isHidden == original.hidden
                && tile.imageData == picture(original.image, in: media) && tile.audioData == nil
        }
    }

    /// A starter picture as an import stores it. If this device would store it differently from the device
    /// that loaded the starter, the tile counts as changed and its board is kept: the safe side.
    private static func picture(_ path: String?, in media: [String: Data]) -> Data? {
        guard let path, let raw = media[path] else { return nil }
        if let done = preparedPictures[path] { return done }
        let ready = ConfigBridge.preparedPicture(raw)
        preparedPictures[path] = ready
        return ready
    }

    private static var preparedPictures: [String: Data?] = [:]
}
