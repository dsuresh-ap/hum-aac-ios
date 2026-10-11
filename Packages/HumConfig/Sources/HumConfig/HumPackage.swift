// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A `.hum` package: a zip with `hum.json` at the root and media files under `media/`.
public enum HumPackage {
    public static let jsonName = "hum.json"
    public static let mediaFolder = "media/"
    public static let fileExtension = "hum"

    public struct Contents: Sendable {
        public var json: Data
        public var media: [String: Data]
    }

    /// Reads a `.hum` zip. Unsafe paths (absolute, `..`) are dropped, so they can never escape a folder.
    public static func read(_ data: Data) throws -> Contents {
        let entries: [ZipArchive.Entry]
        do {
            entries = try ZipArchive.read(data)
        } catch {
            throw HumConfigError.badPackage("It may be damaged or only partly downloaded.")
        }
        // Accept hum.json at the root, or inside a single top-level folder (zips made by Finder).
        let json = entries.first { $0.path == jsonName }
            ?? entries.first { $0.path.hasSuffix("/" + jsonName) && $0.path.split(separator: "/").count == 2 }
        guard let json else { throw HumConfigError.badPackage("It has no hum.json inside.") }

        let prefix = String(json.path.dropLast(jsonName.count))
        var media: [String: Data] = [:]
        for entry in entries where entry.path != json.path && isSafe(entry.path) {
            let relative = entry.path.hasPrefix(prefix) ? String(entry.path.dropFirst(prefix.count)) : entry.path
            if relative.hasPrefix(mediaFolder) { media[relative] = entry.data }
        }
        return Contents(json: json.data, media: media)
    }

    /// Writes a `.hum` zip. Only media referenced by the document is included.
    public static func write(_ document: HumDocument, media: [String: Data]) throws -> Data {
        var entries = [ZipArchive.Entry(path: jsonName, data: try document.encodedJSON())]
        let referenced = Set(document.boards.flatMap { $0.tiles.flatMap { [$0.image, $0.audio].compactMap { $0 } } })
        for path in referenced.sorted() where isSafe(path) {
            if let data = media[path] { entries.append(.init(path: path, data: data)) }
        }
        return ZipArchive.write(entries)
    }

    /// A relative path with no `..`, no leading `/` and no backslashes.
    public static func isSafe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
            && !path.split(separator: "/").contains("..") && !path.contains(":")
    }
}
