// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Changes from Shortcuts, Siri and other automations, waiting for a parent.
///
/// App Intents never change boards directly: the child may be using Hum at that moment. They drop a
/// `.hum` or `hum.json` file in this queue, and the next time a parent opens grown-up settings, Hum
/// shows the normal import preview for each one.
nonisolated enum PendingChanges {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pending", isDirectory: true)
    }

    /// Adds a change to the queue. `name` is shown to the parent ("From Shortcuts: Add a tile").
    static func enqueue(_ data: Data, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = String(format: "%.0f", Date.now.timeIntervalSince1970 * 1000)
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        try data.write(to: directory.appendingPathComponent("\(stamp) \(safe)"), options: .atomic)
    }

    /// Oldest first.
    static func all() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// The parent-facing name, without the timestamp prefix.
    static func displayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        guard let space = name.firstIndex(of: " ") else { return name }
        return String(name[name.index(after: space)...])
    }
}
