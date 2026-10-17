// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Online AAC symbol search for the parent's picture picker: ARASAAC pictograms, or Mulberry symbols
/// through Global Symbols.
///
/// The one network use outside iCloud and Private Cloud Compute, and only when a parent searches:
/// the search word is sent, nothing else (no IDs, no boards, no cookies). A chosen symbol is saved
/// into the tile like a photo, so the child's board never needs the network.
enum SymbolLibrary {
    enum Source: String, CaseIterable, Identifiable, Sendable {
        /// Colorful, closest to the symbols in many AAC apps. CC BY-NC-SA 4.0 (Hum is free).
        case arasaac
        /// Simple, clear line style, made for AAC. CC BY-SA 4.0.
        case mulberry

        var id: String { rawValue }

        var name: String {
            switch self {
            case .arasaac: return "ARASAAC"
            case .mulberry: return "Mulberry"
            }
        }

        /// Required credit (shown in the picker and in Settings → About Hum).
        var credit: String {
            switch self {
            case .arasaac: return "ARASAAC pictograms by Sergio Palao. Origin: ARASAAC (arasaac.org). License: CC BY-NC-SA 4.0. Owner: Government of Aragón (Spain)."
            case .mulberry: return "Mulberry Symbols by Steve Lee (mulberrysymbols.org), via Global Symbols. License: CC BY-SA 4.0."
            }
        }
    }

    struct Symbol: Identifiable, Hashable, Sendable {
        let id: String
        let keyword: String
        let thumbnailURL: URL
        let imageURL: URL
    }

    enum SearchError: LocalizedError {
        case offline
        case failed

        var errorDescription: String? {
            switch self {
            case .offline: return String(localized: "Couldn't reach the symbol library. Check your internet connection and try again.")
            case .failed: return String(localized: "The symbol library didn't answer. Try again in a moment.")
            }
        }
    }

    /// Every credit, for Settings → About Hum.
    static var credits: String { Source.allCases.map(\.credit).joined(separator: "\n") }

    /// No cookies, no cache on disk, nothing that identifies the device.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    // MARK: Search

    /// Symbols for a word or short phrase, best match first. Searches in the device's language; when that
    /// finds nothing, tries English too (a parent may type an English word, and some sets are English only).
    static func search(_ text: String, in source: Source) async throws -> [Symbol] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let wanted = language(for: source), english = language(for: source, code: "en")
        let found = try await search(query, in: source, language: wanted)
        guard found.isEmpty, wanted != english else { return found }
        return try await search(query, in: source, language: english)
    }

    private static func search(_ query: String, in source: Source, language: String) async throws -> [Symbol] {
        guard let url = searchURL(query, source: source, language: language) else { return [] }
        let (data, response) = try await fetch(url)
        // ARASAAC answers 404 when nothing matches.
        if (response as? HTTPURLResponse)?.statusCode == 404 { return [] }
        switch source {
        case .arasaac: return try parse(data)
        case .mulberry: return try parseGlobalSymbols(data)
        }
    }

    static func searchURL(_ query: String, source: Source, language: String) -> URL? {
        switch source {
        case .arasaac:
            guard let word = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) else { return nil }
            return URL(string: "https://api.arasaac.org/v1/pictograms/\(language)/search/\(word)")
        case .mulberry:
            var parts = URLComponents(string: "https://globalsymbols.com/api/v1/labels/search")
            parts?.queryItems = [.init(name: "query", value: query), .init(name: "symbolset", value: "mulberry"),
                                 .init(name: "language", value: language), .init(name: "limit", value: "60")]
            return parts?.url
        }
    }

    /// The language code each service wants: ARASAAC takes two letters ("es"), Global Symbols three ("spa").
    static func language(for source: Source, code: String? = nil) -> String {
        let code = code ?? Locale.current.language.languageCode?.identifier ?? "en"
        switch source {
        case .arasaac: return arasaacLanguages.contains(code) ? code : "en"
        case .mulberry: return Locale.LanguageCode(code).identifier(.alpha3) ?? "eng"
        }
    }

    /// ARASAAC languages Hum asks for; anything else searches in English.
    static let arasaacLanguages: Set<String> = ["en", "es", "fr", "de", "it", "pt", "ca", "eu", "gl", "nl", "pl", "ro",
                                                "ru", "ar", "zh", "bg", "hr", "el", "he", "hu", "sk", "sv", "uk"]

    /// ARASAAC: `[{ "_id": 11461, "keywords": [{ "keyword": "juice" }], "violence": false }]`.
    static func parse(_ data: Data) throws -> [Symbol] {
        struct Item: Decodable {
            struct Keyword: Decodable { let keyword: String }
            let _id: Int
            let keywords: [Keyword]?
            let violence: Bool?
        }
        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { throw SearchError.failed }
        // Skip pictograms ARASAAC marks as violent: this is a child's board.
        return items.filter { $0.violence != true }.prefix(60).compactMap { item in
            let base = "https://static.arasaac.org/pictograms/\(item._id)/\(item._id)"
            guard let thumb = URL(string: base + "_300.png"), let full = URL(string: base + "_500.png") else { return nil }
            return Symbol(id: "arasaac-\(item._id)", keyword: item.keywords?.first?.keyword ?? "", thumbnailURL: thumb, imageURL: full)
        }
    }

    /// Global Symbols: `[{ "id": 44, "text": "Apple", "picto": { "id": 3160, "image_url": "https://…svg" } }]`.
    static func parseGlobalSymbols(_ data: Data) throws -> [Symbol] {
        struct Item: Decodable {
            struct Picto: Decodable {
                let id: Int
                let image_url: String
            }
            let text: String
            let picto: Picto
        }
        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { throw SearchError.failed }
        var seen = Set<Int>()
        return items.compactMap { item in
            guard seen.insert(item.picto.id).inserted, let url = URL(string: item.picto.image_url), url.scheme == "https" else { return nil }
            return Symbol(id: "gs-\(item.picto.id)", keyword: item.text, thumbnailURL: url, imageURL: url)
        }
    }

    // MARK: Download

    /// The picture, ready for `ImageProcessing.tileImageData` (PNG or SVG).
    static func download(_ symbol: Symbol) async throws -> Data {
        let (data, response) = try await fetch(symbol.imageURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SearchError.failed }
        return data
    }

    private static func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                                             .cannotConnectToHost, .timedOut, .dataNotAllowed].contains(error.code) {
            throw SearchError.offline
        } catch {
            throw SearchError.failed
        }
    }
}
