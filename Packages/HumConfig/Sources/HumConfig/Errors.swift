// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One problem found in a config file, written for a parent to read (no stack traces, no jargon).
public struct ValidationIssue: Equatable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }

    public var severity: Severity
    /// A friendly sentence, e.g. "Tile 'snack' has no words to say."
    public var message: String
    /// JSON Pointer to the problem (for agents and developers), e.g. "/boards/0/tiles/3/spokenText".
    public var path: String

    public init(_ severity: Severity, _ message: String, path: String = "") {
        self.severity = severity
        self.message = message
        self.path = path
    }

    public var description: String {
        path.isEmpty ? "\(severity.rawValue): \(message)" : "\(severity.rawValue): \(message) [\(path)]"
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
    case badPackage(String)

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
            return "This .hum file couldn't be opened. \(reason)"
        }
    }
}
