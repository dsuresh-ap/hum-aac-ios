// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import HumConfig

/// What the child said recently, so a communication partner who missed it can see it (and a parent can
/// look back later).
///
/// Stays on this device only: never exported, never synced, never sent anywhere. A parent can clear it.
/// Fast repeated taps of the same tile (often vocal stimming) become one entry with a count, so the
/// history stays readable. Repeating is never treated as a problem.
@MainActor
@Observable
final class SpeechHistory {
    nonisolated struct Entry: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
        var label: String
        var spokenText: String
        var function: TileFunction?
        var colorHex: String?
        var date: Date
        /// How many times in a row it was said.
        var count: Int = 1
    }

    static let maxEntries = 500
    /// Taps of the same phrase closer together than this are counted as one entry.
    static let repeatWindow: TimeInterval = 10

    private(set) var entries: [Entry] = []  // newest last
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// `fileURL` nil keeps history in memory only (tests, UI tests).
    init(fileURL: URL? = SpeechHistory.defaultURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("history.json")
    }

    func add(label: String, spokenText: String, function: TileFunction?, colorHex: String?, at date: Date = .now) {
        guard !spokenText.isEmpty else { return }
        if let last = entries.last, last.spokenText == spokenText, date.timeIntervalSince(last.date) < Self.repeatWindow {
            entries[entries.count - 1].count += 1
            entries[entries.count - 1].date = date
        } else {
            entries.append(Entry(label: label, spokenText: spokenText, function: function, colorHex: colorHex, date: date))
            if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
        }
        scheduleSave()
    }

    /// The most recent entries, newest first.
    func recent(_ n: Int) -> [Entry] { Array(entries.suffix(n).reversed()) }

    func clear() {
        entries.removeAll()
        scheduleSave()
    }

    /// Saves a moment later, off the tap path, so tapping never waits on the disk.
    private func scheduleSave() {
        guard let fileURL else { return }
        saveTask?.cancel()
        let snapshot = entries
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: fileURL, options: .atomic) }
        }
    }
}
