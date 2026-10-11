// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The result of reading a config: the document, any media found next to it, and non-fatal warnings.
public struct LoadedConfig: Sendable {
    public var document: HumDocument
    /// Media files keyed by their relative path (e.g. "media/snack.jpg"). Empty for a plain hum.json.
    public var media: [String: Data]
    public var warnings: [ValidationIssue]

    public init(document: HumDocument, media: [String: Data] = [:], warnings: [ValidationIssue] = []) {
        self.document = document
        self.media = media
        self.warnings = warnings
    }
}

/// Reads `hum.json` or `.hum` data in four steps: version check → migrate → schema → semantic checks.
/// It never crashes on bad input. Every problem becomes a `HumConfigError` with friendly text.
public enum HumConfigLoader {
    /// Loads a `.hum` package (zip) or a plain `hum.json`. The format is detected from the bytes.
    public static func load(_ data: Data) throws -> LoadedConfig {
        if ZipArchive.looksLikeZip(data) {
            let package = try HumPackage.read(data)
            var loaded = try loadJSON(package.json)
            loaded.media = package.media
            loaded.warnings += missingMediaWarnings(loaded.document, media: package.media)
            return loaded
        }
        var loaded = try loadJSON(data)
        loaded.warnings += missingMediaWarnings(loaded.document, media: [:])
        return loaded
    }

    /// Loads plain `hum.json` bytes.
    public static func loadJSON(_ data: Data) throws -> LoadedConfig {
        var json = try JSONValue.parse(data)

        guard case .object = json else {
            throw HumConfigError.invalid([.init(.error, "The file should start with { and contain \"formatVersion\" and \"boards\".")])
        }
        guard let version = json["formatVersion"]?.intValue else {
            throw HumConfigError.invalid([.init(.error, "The file has no 'formatVersion'. Add \"formatVersion\": 1 at the top.", path: "/formatVersion")])
        }
        if version > HumDocument.currentFormatVersion {
            throw HumConfigError.newerFormat(found: version, supported: HumDocument.currentFormatVersion)
        }
        json = try Migrations.migrate(json, from: version)

        let schemaIssues = SchemaValidator.hum.validate(json)
        if !schemaIssues.isEmpty { throw HumConfigError.invalid(schemaIssues) }

        let document: HumDocument
        do {
            let migrated = try JSONEncoder().encode(json)
            document = try JSONDecoder().decode(HumDocument.self, from: migrated)
        } catch {
            // Should not happen after schema validation; still never crash.
            throw HumConfigError.invalid([.init(.error, "The file has a shape Hum doesn't understand.")])
        }

        let issues = HumValidator.semanticIssues(in: document)
        if issues.contains(where: { $0.severity == .error }) { throw HumConfigError.invalid(issues) }
        return LoadedConfig(document: document, media: [:], warnings: issues)
    }

    /// Validates without throwing. Returns every issue (errors and warnings) for the CLI and the app.
    public static func validate(_ data: Data) -> [ValidationIssue] {
        do {
            return try load(data).warnings
        } catch let error as HumConfigError {
            switch error {
            case .invalid(let issues): return issues
            default: return [.init(.error, error.errorDescription ?? "Unknown problem.")]
            }
        } catch {
            return [.init(.error, "Unknown problem: \(error.localizedDescription)")]
        }
    }

    static func missingMediaWarnings(_ doc: HumDocument, media: [String: Data]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for board in doc.boards {
            for tile in board.tiles {
                for path in [tile.image, tile.audio].compactMap({ $0 }) where media[path] == nil {
                    issues.append(.init(.warning, "Tile '\(tile.label)' points to '\(path)', which isn't in the file. The tile still works without it."))
                }
            }
        }
        return issues
    }
}

/// Upgrades older `formatVersion`s to the current one, one step at a time.
/// When you bump `HumDocument.currentFormatVersion`, add a step here and a test with an old file.
enum Migrations {
    static func migrate(_ json: JSONValue, from version: Int) throws -> JSONValue {
        guard version >= 1 else {
            throw HumConfigError.invalid([.init(.error, "Format version \(version) is not supported.", path: "/formatVersion")])
        }
        // Version 1 is current. Future steps go here, e.g.:
        // var json = json
        // if version < 2 { json = migrate1to2(json) }
        return json
    }
}
