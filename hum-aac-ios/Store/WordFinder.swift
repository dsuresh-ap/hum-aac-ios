// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import NaturalLanguage

/// Finds tiles and boards by their words, and shows the way to them from Home.
///
/// Exact matches come first. "Might be related" matches use Apple's on-device word meanings
/// (NaturalLanguage), so "drink" can find "juice". Nothing leaves the device.
nonisolated struct WordFinder: Sendable {
    /// One step on the way: on `boardID`, press `tileID`.
    struct Step: Hashable, Sendable {
        let boardID: UUID
        let tileID: UUID
    }

    struct Result: Identifiable, Hashable, Sendable {
        enum Kind: Hashable, Sendable { case tile, board }
        let kind: Kind
        /// The tile's or the board's ID.
        let id: UUID
        let label: String
        let spokenText: String
        let symbol: String?
        /// The board the tile is on (for a board result, the board itself).
        let boardID: UUID
        /// Board names from Home to here, e.g. ["Home", "Food"].
        let path: [String]
        /// Presses from Home: folders, then the tile. Nil when no folder on the way links to it.
        let route: [Step]?
        let related: Bool

        var pathText: String { path.joined(separator: " › ") }
    }

    /// A tile, copied out of the store so searching can run anywhere.
    struct Entry: Sendable {
        let tileID: UUID
        let boardID: UUID
        let label: String
        let spokenText: String
        let symbol: String?
        let linkedBoardID: UUID?
        let isHidden: Bool
    }

    struct BoardEntry: Sendable {
        let id: UUID
        let name: String
        let isHome: Bool
    }

    let boards: [BoardEntry]
    let tiles: [Entry]
    /// Route from Home to each board (the folder tiles to press). Home's is empty.
    let routes: [UUID: [Step]]
    /// Content words per tile ("Let's have a snack" → snack), for related matches.
    private let words: [UUID: [String]]
    /// The language the tiles are written in, for word meanings.
    private let language: NLLanguage?

    init(boards: [BoardEntry], tiles: [Entry]) {
        self.boards = boards
        self.tiles = tiles
        self.routes = Self.routes(boards: boards, tiles: tiles)
        var words: [UUID: [String]] = [:]
        for tile in tiles where !tile.isHidden {
            words[tile.tileID] = Self.contentWords("\(tile.label) \(tile.spokenText)")
        }
        self.words = words
        language = NLLanguageRecognizer.dominantLanguage(for: tiles.prefix(300).map(\.spokenText).joined(separator: ". "))
    }

    /// Copies every board and tile out of the store.
    @MainActor
    init(boards: [Board]) {
        self.init(
            boards: boards.map { BoardEntry(id: $0.id, name: $0.name, isHome: $0.isHome) },
            tiles: boards.flatMap { board in
                board.placedTiles.map {
                    Entry(tileID: $0.id, boardID: board.id, label: $0.label, spokenText: $0.spokenText,
                          symbol: $0.symbol, linkedBoardID: $0.linkedBoardID, isHidden: $0.isHidden)
                }
            })
    }

    // MARK: Searching

    /// Exact matches first (label start, then any word start, then anywhere), then up to
    /// `relatedLimit` tiles with a related meaning. Hidden tiles are never found.
    func search(_ query: String, relatedLimit: Int = 8) -> [Result] {
        let q = Self.normalized(query)
        guard !q.isEmpty else { return [] }
        var scored: [(Int, Result)] = []
        for board in boards where !board.isHome {
            let name = Self.normalized(board.name)
            if let rank = Self.rank(of: q, in: name) {
                scored.append((rank, result(for: board)))
            }
        }
        for tile in tiles where !tile.isHidden {
            let ranks = [Self.rank(of: q, in: Self.normalized(tile.label)),
                         Self.rank(of: q, in: Self.normalized(tile.spokenText)).map { $0 + 1 }].compactMap { $0 }
            if let rank = ranks.min(), let found = result(for: tile, related: false) {
                scored.append((rank, found))
            }
        }
        let exact = scored.sorted { ($0.0, $0.1.path.count, $0.1.label) < ($1.0, $1.1.path.count, $1.1.label) }.map(\.1)
        let found = Set(exact.map(\.id))
        return exact + related(to: query, excluding: found, limit: relatedLimit)
    }

    /// Tiles whose words mean something close to the query's, closest first.
    private func related(to query: String, excluding found: Set<UUID>, limit: Int) -> [Result] {
        let queryWords = Self.contentWords(query)
        guard limit > 0, !queryWords.isEmpty, queryWords.count <= 3,
              let embedding = Self.embedding(preferring: language) else { return [] }
        var close: [(Double, Entry)] = []
        for tile in tiles where !tile.isHidden && !found.contains(tile.tileID) {
            let distances = queryWords.flatMap { q in (words[tile.tileID] ?? []).map { embedding.distance(between: q, and: $0) } }
            if let best = distances.min(), best < Self.relatedCutoff { close.append((best, tile)) }
        }
        return close.sorted { $0.0 < $1.0 }.prefix(limit).compactMap { result(for: $0.1, related: true) }
    }

    /// Cosine distance (0 = same, 2 = opposite) under which a word counts as related. Picked by trying
    /// common tile words: "vehicle" → car, bus; "noise" → "It's too loud"; "eat" → snack.
    static let relatedCutoff = 1.0

    private func result(for tile: Entry, related: Bool) -> Result? {
        let route = routes[tile.boardID].map { $0 + [Step(boardID: tile.boardID, tileID: tile.tileID)] }
        return Result(kind: .tile, id: tile.tileID, label: tile.label, spokenText: tile.spokenText, symbol: tile.symbol,
                      boardID: tile.boardID, path: path(to: tile.boardID), route: route, related: related)
    }

    private func result(for board: BoardEntry) -> Result {
        Result(kind: .board, id: board.id, label: board.name, spokenText: "", symbol: nil, boardID: board.id,
               path: Array(path(to: board.id).dropLast()), route: routes[board.id], related: false)
    }

    /// Board names along the route, ending with the board itself.
    private func path(to boardID: UUID) -> [String] {
        let names = Dictionary(boards.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        guard let route = routes[boardID] else { return [names[boardID] ?? ""] }
        return route.map { names[$0.boardID] ?? "" } + [names[boardID] ?? ""]
    }

    // MARK: Helpers

    /// Shortest way from Home to every board it can reach, through visible folder tiles.
    private static func routes(boards: [BoardEntry], tiles: [Entry]) -> [UUID: [Step]] {
        guard let home = boards.first(where: \.isHome) ?? boards.first else { return [:] }
        let folders = Dictionary(grouping: tiles.filter { $0.linkedBoardID != nil && !$0.isHidden }, by: \.boardID)
        var routes: [UUID: [Step]] = [home.id: []]
        var queue = [home.id]
        while !queue.isEmpty {
            let board = queue.removeFirst()
            for folder in folders[board] ?? [] {
                guard let next = folder.linkedBoardID, routes[next] == nil else { continue }
                routes[next] = (routes[board] ?? []) + [Step(boardID: board, tileID: folder.tileID)]
                queue.append(next)
            }
        }
        return routes
    }

    /// 0 = the text starts with the query, 2 = a word starts with it, 4 = it's somewhere inside.
    private static func rank(of query: String, in text: String) -> Int? {
        guard let range = text.range(of: query) else { return nil }
        if range.lowerBound == text.startIndex { return 0 }
        return text.contains(" " + query) ? 2 : 4
    }

    /// Lowercased, without accents or punctuation, single spaces: "Let's GO!" → "lets go".
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let kept = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(kept)).split(separator: " ").joined(separator: " ")
    }

    /// Words that carry meaning (nouns, verbs, adjectives…), as their dictionary form: "Let's have a
    /// snack" → ["snack"]. Little words like "have" and "need" would make everything look related.
    static func contentWords(_ text: String) -> [String] {
        let lower = text.lowercased()
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = lower
        var words: [String] = []
        tagger.enumerateTags(in: lower.startIndex..<lower.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace, .omitOther]) { tag, range in
            // A tile that is one word ("car") often gets no word class at all: keep those too.
            guard let tag, [.noun, .verb, .adjective, .adverb, .interjection, .otherWord].contains(tag) else { return true }
            let word = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue ?? String(lower[range])
            if word.count > 2, !littleWords.contains(word) { words.append(word) }
            return true
        }
        return words
    }

    private static let littleWords: Set<String> = ["let", "have", "need", "want", "get", "make", "too", "really", "just"]

    /// Word meanings for the tiles' language, falling back to the device language, then English.
    private static func embedding(preferring language: NLLanguage?) -> NLEmbedding? {
        var candidates: [NLLanguage] = []
        if let language { candidates.append(language) }
        if let code = Locale.current.language.languageCode?.identifier { candidates.append(NLLanguage(code)) }
        candidates.append(.english)
        for language in candidates {
            if let embedding = NLEmbedding.wordEmbedding(for: language) { return embedding }
        }
        return nil
    }
}
