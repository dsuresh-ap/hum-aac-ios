// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One problem found in a config file, written for a parent to read (no stack traces, no jargon).
public struct ValidationIssue: Equatable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }

    public var severity: Severity
    /// What is wrong. Apps show it in their own language; `message` is the English sentence.
    public var problem: ConfigProblem
    /// JSON Pointer to the problem (for agents and developers), e.g. "/boards/0/tiles/3/spokenText".
    public var path: String

    public init(_ severity: Severity, _ problem: ConfigProblem, path: String = "") {
        self.severity = severity
        self.problem = problem
        self.path = path
    }

    /// An issue with a ready-made English sentence (for checks that have no `ConfigProblem` case).
    public init(_ severity: Severity, _ message: String, path: String = "") {
        self.init(severity, .other(message), path: path)
    }

    /// A friendly English sentence, e.g. "Tile 'snack' has no words to say."
    public var message: String { problem.text }

    public var description: String {
        path.isEmpty ? "\(severity.rawValue): \(message)" : "\(severity.rawValue): \(message) [\(path)]"
    }
}

/// Which board or tile an issue is about.
public enum ConfigSubject: Sendable, Equatable {
    /// A tile, by its label (or its words when it has no label).
    case tile(String)
    /// A tile with no words or label: its number on a board (1-based) and the board's name, if it has one.
    case tileNumber(Int, boardName: String?, boardNumber: Int)
    case board(String)
    /// A board with no name: its number in the file (1-based).
    case boardNumber(Int)
    case settings
    case file

    /// English, e.g. "Tile 'snack'" or "Board 2".
    public var text: String {
        switch self {
        case .tile(let name): return "Tile '\(name)'"
        case .tileNumber(let n, let boardName, let boardNumber): return "Tile \(n) on '\(boardName ?? "board \(boardNumber)")'"
        case .board(let name): return "Board '\(name)'"
        case .boardNumber(let n): return "Board \(n)"
        case .settings: return "Settings"
        case .file: return "The file"
        }
    }
}

/// Everything HumConfig can find wrong with a file. `text` is the English sentence; the app translates
/// each case itself (HumConfig has no String Catalog, because it also builds on Linux).
public enum ConfigProblem: Sendable, Equatable {
    // Schema checks. `field` is the JSON key, e.g. "spokenText".
    case noWords(ConfigSubject)
    case emptyLabel(ConfigSubject)
    case noName(ConfigSubject)
    case missingID(ConfigSubject)
    case invalidID(ConfigSubject, field: String)
    case noPlace(ConfigSubject)
    case noFormatVersion
    case missingField(ConfigSubject, field: String)
    /// `expected` holds JSON type names: "integer", "number", "string", "boolean", "array", "object".
    case wrongType(ConfigSubject, field: String, expected: [String])
    case notOneOf(ConfigSubject, field: String, options: [String])
    case mustBe(ConfigSubject, field: String, value: String)
    case tooShort(ConfigSubject, field: String, min: Int)
    case tooLong(ConfigSubject, field: String, max: Int)
    case badColor(ConfigSubject)
    case wrongFormat(ConfigSubject, field: String)
    /// `min` and `max` are written as in the file, or "…" when there is no limit on that side.
    case outOfRange(ConfigSubject, field: String, min: String, max: String)
    case tooFewItems(ConfigSubject, field: String, min: Int)
    case tooManyItems(ConfigSubject, field: String, max: Int)
    case notAllowed(ConfigSubject, field: String)
    // Checks on the whole file.
    case notAnObject
    case unknownShape
    case unsupportedVersion(Int)
    case severalHomes([String])
    case duplicateBoardID(ConfigSubject)
    case boardTooSmall(ConfigSubject)
    case duplicateTileID(ConfigSubject)
    case folderNeedsLabel(board: ConfigSubject)
    case outsideGrid(ConfigSubject, board: ConfigSubject, row: Int, column: Int, rows: Int, columns: Int)
    case sameSpot(ConfigSubject, otherTile: String, row: Int, column: Int, board: ConfigSubject)
    case missingLink(ConfigSubject)
    case creditWithoutPicture(ConfigSubject)
    case praisePhrase(ConfigSubject, phrase: String)
    case missingMedia(tile: String, path: String)
    /// Anything else, already in words.
    case other(String)

    public var text: String {
        switch self {
        case .noWords(let s): return "\(s.text) has no words to say."
        case .emptyLabel(let s): return "\(s.text) has an empty label."
        case .noName(let s): return "\(s.text) has no name."
        case .missingID(let s): return "\(s.text) is missing its ID. Every board and tile needs a UUID."
        case .invalidID(let s, let field):
            return "\(s.text): '\(field)' is not a valid ID. It should be a UUID like 3F2504E0-4F89-11D3-9A0C-0305E82C3301."
        case .noPlace(let s): return "\(s.text) has no place on the grid (it needs both 'row' and 'column')."
        case .noFormatVersion: return "The file has no 'formatVersion'. Add \"formatVersion\": 1 at the top."
        case .missingField(let s, let field): return "\(s.text) is missing '\(field)'."
        case .wrongType(let s, let field, let expected):
            return "\(s.text): '\(field)' should be \(expected.map(Self.typeName).joined(separator: " or "))."
        case .notOneOf(let s, let field, let options): return "\(s.text): '\(field)' must be one of: \(options.joined(separator: ", "))."
        case .mustBe(let s, let field, let value): return "\(s.text): '\(field)' must be \(value)."
        case .tooShort(let s, let field, let n): return "\(s.text): '\(field)' must have at least \(n) character\(n == 1 ? "" : "s")."
        case .tooLong(let s, let field, let n): return "\(s.text): '\(field)' is too long (at most \(n) characters)."
        case .badColor(let s): return "\(s.text): 'color' should look like #A1B2C3."
        case .wrongFormat(let s, let field): return "\(s.text): '\(field)' has the wrong format."
        case .outOfRange(let s, let field, let lo, let hi): return "\(s.text): '\(field)' must be between \(lo) and \(hi)."
        case .tooFewItems(let s, let field, let n): return "\(s.text): '\(field)' needs at least \(n) item\(n == 1 ? "" : "s")."
        case .tooManyItems(let s, let field, let n): return "\(s.text): '\(field)' can have at most \(n) items."
        case .notAllowed(let s, let field): return "\(s.text): '\(field)' is not allowed here."
        case .notAnObject: return "The file should start with { and contain \"formatVersion\" and \"boards\"."
        case .unknownShape: return "The file has a shape Hum doesn't understand."
        case .unsupportedVersion(let v): return "Format version \(v) is not supported."
        case .severalHomes(let names):
            return "More than one board is marked as Home (\(names.map { "'\($0)'" }.joined(separator: ", "))). Only one can be Home."
        case .duplicateBoardID(let s): return "\(s.text) has the same ID as another board. Every board needs its own ID."
        case .boardTooSmall(let s): return "\(s.text) is too small. The smallest grid is 1 × 2."
        case .duplicateTileID(let s): return "\(s.text) has the same ID as another tile. Every tile needs its own ID."
        case .folderNeedsLabel(let board): return "A folder tile on \(board.text) needs a label or words to say."
        case .outsideGrid(let s, let board, let row, let column, let rows, let columns):
            return "\(s.text) is outside the grid of \(board.text) (row \(row), column \(column); the grid is \(rows) rows × \(columns) columns, counting from 0)."
        case .sameSpot(let s, let other, let row, let column, let board):
            return "\(s.text) and tile '\(other)' are in the same spot (row \(row), column \(column)) on \(board.text)."
        case .missingLink(let s): return "\(s.text) opens a board that isn't in this file. It will still speak; the link is ignored until that board exists."
        case .creditWithoutPicture(let s): return "\(s.text) has a picture credit but no picture. The credit is kept, but it has nothing to describe."
        case .praisePhrase(let s, let phrase): return "\(s.text) uses \"\(phrase)\". Hum avoids praise, reward and compliance phrases. Tiles are the child's voice."
        case .missingMedia(let tile, let path): return "Tile '\(tile)' points to '\(path)', which isn't in the file. The tile still works without it."
        case .other(let text): return text
        }
    }

    /// "integer" → "a whole number", for the English sentence.
    static func typeName(_ type: String) -> String {
        switch type {
        case "integer": return "a whole number"
        case "number": return "a number"
        case "string": return "text"
        case "boolean": return "true or false"
        case "array": return "a list"
        case "object": return "an object"
        default: return type
        }
    }
}

/// Why a `.hum` package couldn't be opened.
public enum PackageProblem: Sendable, Equatable {
    /// Not a readable zip (damaged, or only partly downloaded).
    case damaged
    /// A zip with no hum.json inside.
    case noConfig
    /// The file couldn't be read at all.
    case unreadable
    /// Too many files inside, or too big once unpacked (see `ZipArchive.maxTotalSize`).
    case tooBig

    public var text: String {
        switch self {
        case .damaged: return "It may be damaged or only partly downloaded."
        case .noConfig: return "It has no hum.json inside."
        case .unreadable: return "Hum couldn't read the file."
        case .tooBig: return "It is too big to open (more than 600 MB once unpacked)."
        }
    }
}

public enum HumConfigError: Error, Equatable, Sendable, LocalizedError {
    /// The bytes are not JSON (and not a zip).
    case notJSON
    /// The file was made by a newer Hum.
    case newerFormat(found: Int, supported: Int)
    /// The file has problems; `issues` contains at least one `.error`.
    case invalid([ValidationIssue])
    /// The `.hum` package is not a valid zip or has no `hum.json`.
    case badPackage(PackageProblem)

    public var errorDescription: String? {
        switch self {
        case .notJSON:
            return "This file isn't a Hum setup. It should be a .hum file or a hum.json file."
        case .newerFormat:
            return "This setup was made with a newer version of Hum. Please update Hum to open it."
        case .invalid(let issues):
            let errors = issues.filter { $0.severity == .error }.map(\.message)
            let shown = errors.prefix(5).joined(separator: "\n")
            let more = errors.count > 5 ? "\n…and \(errors.count - 5) more." : ""
            return "This setup has some problems:\n\(shown)\(more)"
        case .badPackage(let reason):
            return "This .hum file couldn't be opened. \(reason.text)"
        }
    }
}
