// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A `.hum` package: a zip with `hum.json` at the root and media files under `media/`.
public enum HumPackage {
    public static let jsonName = "hum.json"
    public static let mediaFolder = "media/"
    public static let fileExtension = "hum"
    /// Picture credits, written at the root when a tile has an `imageCredit`. Never read as media.
    public static let creditsName = "CREDITS.txt"
    static let creditsNote = "Some pictures in this file come from the symbol sets above and keep their licences."

    public struct Contents: Sendable {
        public var json: Data
        public var media: [String: Data]
        /// `CREDITS.txt`, if the package has one. Only for people reading the file; Hum reads credits
        /// from each tile's `imageCredit`.
        public var credits: Data? = nil
    }

    /// Reads a `.hum` zip. Unsafe paths (absolute, `..`) are dropped, so they can never escape a folder.
    public static func read(_ data: Data) throws -> Contents {
        let entries: [ZipArchive.Entry]
        do {
            entries = try ZipArchive.read(data)
        } catch ZipArchive.ReadError.tooBig {
            throw HumConfigError.badPackage(.tooBig)
        } catch let error as CancellationError {
            throw error  // the app stopped reading; not a damaged file
        } catch {
            throw HumConfigError.badPackage(.damaged)
        }
        // Accept hum.json at the root, or inside a single top-level folder (zips made by Finder).
        let json = entries.first { $0.path == jsonName }
            ?? entries.first { $0.path.hasSuffix("/" + jsonName) && $0.path.split(separator: "/").count == 2 }
        guard let json else { throw HumConfigError.badPackage(.noConfig) }

        let prefix = String(json.path.dropLast(jsonName.count))
        var media: [String: Data] = [:]
        var credits: Data?
        for entry in entries where entry.path != json.path && isSafe(entry.path) {
            let relative = entry.path.hasPrefix(prefix) ? String(entry.path.dropFirst(prefix.count)) : entry.path
            if relative.hasPrefix(mediaFolder) { media[relative] = entry.data }
            if relative == creditsName { credits = entry.data }
        }
        return Contents(json: json.data, media: media, credits: credits)
    }

    /// Writes a `.hum` zip. Only media referenced by the document is included, plus `CREDITS.txt` when
    /// a tile's picture has a credit (symbol licences ask for the credit to travel with the pictures).
    public static func write(_ document: HumDocument, media: [String: Data]) throws -> Data {
        var entries = [ZipArchive.Entry(path: jsonName, data: try document.encodedJSON())]
        if let credits = creditsText(for: document) {
            entries.append(.init(path: creditsName, data: Data(credits.utf8)))
        }
        let referenced = Set(document.boards.flatMap { $0.tiles.flatMap { [$0.image, $0.audio].compactMap { $0 } } })
        for path in referenced.sorted() where isSafe(path) {
            if let data = media[path] { entries.append(.init(path: path, data: data)) }
        }
        return ZipArchive.write(entries)
    }

    /// One line per different credit, then a short note. Nil when no tile has a credit.
    public static func creditsText(for document: HumDocument) -> String? {
        var seen: Set<String> = []
        var lines: [String] = []
        for tile in document.boards.flatMap(\.tiles) {
            guard let credit = tile.imageCredit?.trimmingCharacters(in: .whitespacesAndNewlines), !credit.isEmpty else { continue }
            // Credits are single lines; keep it that way so "one line per credit" holds.
            let line = credit.split(whereSeparator: \.isNewline).joined(separator: " ")
            if seen.insert(line).inserted { lines.append(line) }
        }
        guard !lines.isEmpty else { return nil }
        return (lines + ["", creditsNote]).joined(separator: "\n") + "\n"
    }

    /// A relative path with no `..`, no leading `/` and no backslashes.
    public static func isSafe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
            && !path.split(separator: "/").contains("..") && !path.contains(":")
    }
}
