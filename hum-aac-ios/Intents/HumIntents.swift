// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import Foundation
import SwiftData
import UniformTypeIdentifiers
import HumConfig

// Parent-facing Shortcuts and Siri actions. They let other apps, automations and agents on the device
// prepare changes, but nothing changes until a parent sees the import preview in Hum.

struct AddTileIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Tile to Hum"
    static let description = IntentDescription("Prepares a new tile with a whole phrase. A grown-up confirms it the next time they open Hum's grown-up settings.")

    @Parameter(title: "What the tile says", description: "One whole phrase, just as the child says it.")
    var phrase: String

    @Parameter(title: "Label", description: "Short words shown on the tile. Leave empty to use the phrase.")
    var label: String?

    @Parameter(title: "Board name", description: "Which board. Leave empty for Home.")
    var boardName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$phrase) to Hum") {
            \.$label
            \.$boardName
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw IntentError.message("The tile needs a phrase to say.") }
        if GLPRules.discouragedPhrase(in: text) != nil {
            throw IntentError.message("Hum tiles are the child's own voice, so praise and instruction phrases aren't added.")
        }
        let document = try await MainActor.run { try IntentSupport.documentAddingTile(text: text, label: label, boardName: boardName) }
        try PendingChanges.enqueue(try document.encodedJSON(), name: "From Shortcuts: add “\(text)”.json")
        return .result(dialog: "Ready. A grown-up will see “\(text)” the next time they open Hum's grown-up settings.")
    }
}

struct ImportHumConfigIntent: AppIntent {
    static let title: LocalizedStringResource = "Import a Hum Setup"
    static let description = IntentDescription("Queues a .hum or hum.json file. A grown-up sees a preview and chooses Merge or Replace in Hum.")

    // Type identifiers (not UTTypes) so this works on iOS 17 / macOS 14.
    @Parameter(title: "Setup file", supportedTypeIdentifiers: ["com.dhananjaysuresh.hum-aac.hum", "public.json", "public.zip-archive"])
    var file: IntentFile

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let issues = HumConfigLoader.validate(file.data)
        if let error = issues.first(where: { $0.severity == .error }) {
            throw IntentError.message("This setup has a problem: \(error.message)")
        }
        try PendingChanges.enqueue(file.data, name: "From Shortcuts: \(file.filename)")
        return .result(dialog: "Ready. A grown-up will see a preview the next time they open Hum's grown-up settings.")
    }
}

struct ExportHumSetupIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Hum Setup"
    static let description = IntentDescription("Makes a .hum file with all boards, photos and recordings.")

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let (data, name) = try await MainActor.run { (try IntentSupport.exportAll(), ImportService.exportFileName()) }
        let file = IntentFile(data: data, filename: name, type: .humPackage)
        return .result(value: file)
    }
}

struct HumShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTileIntent(), phrases: ["Add a tile to \(.applicationName)"], shortTitle: "Add a Tile", systemImageName: "plus.square")
        AppShortcut(intent: ExportHumSetupIntent(), phrases: ["Export my \(.applicationName) setup"], shortTitle: "Export Setup", systemImageName: "square.and.arrow.up")
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case message(String)
    var localizedStringResource: LocalizedStringResource {
        switch self { case .message(let text): return "\(text)" }
    }
}

/// Reads the store for intents. Uses its own read-only context; never writes boards.
@MainActor
enum IntentSupport {
    private static func boards() throws -> [Board] {
        let container = Persistence.makeContainer()
        return try ModelContext(container).fetch(FetchDescriptor<Board>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    static func exportAll() throws -> Data {
        let (document, media) = ConfigBridge.export(boards: try boards())
        return try HumPackage.write(document, media: media)
    }

    /// A one-tile document aimed at the first free spot of the chosen board. If the board fills up
    /// before a parent applies it, the merge planner puts the tile in the "needs a spot" tray instead.
    static func documentAddingTile(text: String, label: String?, boardName: String?) throws -> HumDocument {
        let all = try boards()
        let target = boardName.flatMap { name in all.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } }
            ?? all.first(where: \.isHome) ?? all.first
        guard let target else { throw IntentError.message("Hum has no boards yet. Open Hum to set it up first.") }
        let taken = Set(target.placedTiles.map { "\($0.row ?? -1),\($0.column ?? -1)" })
        // If the board is full, ask for a taken spot: the merge planner then puts the tile in the
        // "needs a spot" tray, and nothing moves.
        var spot = (row: 0, column: 0)
        search: for r in 0..<target.rows {
            for c in 0..<target.columns where !taken.contains("\(r),\(c)") {
                spot = (r, c)
                break search
            }
        }
        let finalLabel = (label?.isEmpty == false ? label! : TileEditorSheet.suggestLabel(text))
        let tile = HumTile(label: finalLabel, spokenText: text, row: spot.row, column: spot.column)
        let board = HumBoard(id: target.id, name: target.name, rows: target.rows, columns: target.columns,
                             isHome: target.isHome, tiles: [tile])
        return HumDocument(boards: [board])
    }
}
