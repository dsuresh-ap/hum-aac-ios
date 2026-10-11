// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Online AAC symbol search (ARASAAC pictograms), for the parent's picture picker.
///
/// The one network use outside iCloud and Private Cloud Compute, and only when a parent searches:
/// the search word is sent to ARASAAC, nothing else (no IDs, no boards, no cookies). A chosen symbol
/// is saved into the tile like a photo, so the child's board never needs the network.
enum SymbolLibrary {
    struct Symbol: Identifiable, Hashable, Sendable {
        let id: Int
        let keyword: String
        var thumbnailURL: URL { URL(string: "https://static.arasaac.org/pictograms/\(id)/\(id)_300.png")! }
        var imageURL: URL { URL(string: "https://static.arasaac.org/pictograms/\(id)/\(id)_500.png")! }
    }

    enum SearchError: LocalizedError {
        case offline
        case failed

        var errorDescription: String? {
            switch self {
            case .offline: return "Couldn't reach the symbol library. Check your internet connection and try again."
            case .failed: return "The symbol library didn't answer. Try again in a moment."
            }
        }
    }

    /// Required credit for ARASAAC pictograms (CC BY-NC-SA 4.0).
    static let credit = "Symbols: pictograms by Sergio Palao. Origin: ARASAAC (arasaac.org). License: CC BY-NC-SA 4.0. Owner: Government of Aragón (Spain)."

    /// No cookies, no cache on disk, nothing that identifies the device.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// ARASAAC languages Hum asks for; anything else searches in English.
    static let languages: Set<String> = ["en", "es", "fr", "de", "it", "pt", "ca", "eu", "gl", "nl", "pl", "ro", "ru",
                                         "ar", "zh", "bg", "hr", "el", "he", "hu", "sk", "sv", "uk"]

    static var language: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return languages.contains(code) ? code : "en"
    }

    /// Symbols for a word or short phrase, best match first.
    static func search(_ text: String, language: String = language) async throws -> [Symbol] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))),
              let url = URL(string: "https://api.arasaac.org/v1/pictograms/\(language)/search/\(encoded)") else { return [] }
        let (data, response) = try await fetch(url)
        // ARASAAC answers 404 when nothing matches.
        if (response as? HTTPURLResponse)?.statusCode == 404 { return [] }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> [Symbol] {
        struct Item: Decodable {
            struct Keyword: Decodable { let keyword: String }
            let _id: Int
            let keywords: [Keyword]?
            let violence: Bool?
        }
        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { throw SearchError.failed }
        // Skip pictograms ARASAAC marks as violent: this is a child's board.
        return items.filter { $0.violence != true }.prefix(60).map {
            Symbol(id: $0._id, keyword: $0.keywords?.first?.keyword ?? "")
        }
    }

    /// The full-size picture, ready to save into a tile.
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
