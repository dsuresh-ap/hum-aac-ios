// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig

/// The required preview before any import changes anything.
/// "3 new tiles, 2 changed tiles, 0 removed. No tiles will move." → Merge (default) or Replace everything.
struct ImportPreviewSheet: View {
    let pending: PendingImport
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode: MergePlanner.Mode = .merge
    @State private var confirmReplace = false
    @State private var errorMessage: String?
    /// Set while the import runs; the sheet shows a progress bar and can't be closed.
    @State private var progress: ImportService.Progress?

    private var plan: MergePlanner.Plan { mode == .merge ? pending.merge : pending.replace }

    var body: some View {
        NavigationStack {
            Form {
                if let progress {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            if let fraction = progress.fraction {
                                ProgressView(value: fraction)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                            Text(progress.message).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("importProgress")
                    }
                }

                Section {
                    Text(plan.summary.sentence)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("importSummary")
                } header: {
                    Text(pending.fileName)
                }

                Section {
                    Picker("How", selection: $mode) {
                        Text("Merge").tag(MergePlanner.Mode.merge)
                        Text("Replace everything").tag(MergePlanner.Mode.replace)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(mode == .merge
                         ? "Adds new tiles and updates matching ones. Nothing already on your boards moves or is deleted."
                         : "Your boards become exactly what's in this file. Hum saves a backup of your current boards first.")
                }

                if !changedTiles.isEmpty || !newTiles.isEmpty {
                    Section("What changes") {
                        ForEach(newTiles, id: \.id) { tile in
                            Label { Text(Self.describe(tile)) } icon: { Image(systemName: "plus.circle.fill").foregroundStyle(.green) }
                        }
                        ForEach(changedTiles, id: \.id) { tile in
                            Label { Text(Self.describe(tile)) } icon: { Image(systemName: "pencil.circle.fill").foregroundStyle(.blue) }
                        }
                        let more = allNewCount + allChangedCount - newTiles.count - changedTiles.count
                        if more > 0 {
                            Text("and \(more) more").foregroundStyle(.secondary)
                        }
                    }
                }

                let warnings = pending.loaded.warnings
                if !warnings.isEmpty {
                    Section("Good to know") {
                        ForEach(Array(warnings.prefix(8).enumerated()), id: \.offset) { _, issue in
                            Label(issue.message, systemImage: "info.circle").font(.callout)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import a setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(progress != nil) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .merge ? "Merge" : "Replace…") {
                        if mode == .merge { apply() } else { confirmReplace = true }
                    }
                    .disabled(progress != nil)
                    .accessibilityIdentifier("applyImport")
                }
            }
            .confirmationDialog("Replace all your boards?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Replace everything", role: .destructive) { apply() }
            } message: {
                Text("\(pending.replace.summary.sentence) A backup of your current boards is saved first, and you can undo.")
            }
            .alert("Import didn't work", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .disabled(progress != nil)
        }
        .interactiveDismissDisabled(progress != nil)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 460)
        #endif
    }

    private var allIncomingTiles: [HumTile] {
        plan.result.boards.flatMap(\.tiles) + plan.unplaced.map(\.tile)
    }
    private var newTiles: [HumTile] { allIncomingTiles.filter { plan.newTileIDs.contains($0.id) }.prefix(30).map { $0 } }
    private var changedTiles: [HumTile] { allIncomingTiles.filter { plan.changedTileIDs.contains($0.id) }.prefix(30).map { $0 } }
    private var allNewCount: Int { plan.newTileIDs.count }
    private var allChangedCount: Int { plan.changedTileIDs.count }

    /// One line per tile: “Let's go!”, or “snack: Let's have a snack.”, or “Chat (opens a folder)”.
    static func describe(_ tile: HumTile) -> String {
        let phrase = tile.spokenText.trimmingCharacters(in: .whitespaces)
        if phrase.isEmpty { return tile.linkedBoardID != nil ? "\(tile.label) (opens a folder)" : tile.label }
        let bare = { (text: String) in text.trimmingCharacters(in: .punctuationCharacters).lowercased() }
        if bare(phrase) == bare(tile.label) { return "“\(phrase)”" }
        return "\(tile.label): “\(phrase)”"
    }

    private func apply() {
        guard progress == nil else { return }
        progress = .pictures(done: 0, total: 0)
        Task {
            defer { progress = nil }
            do {
                try await ImportService(model: model).apply(pending, mode: mode) { progress = $0 }
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// Shows the import preview (and import errors) for `model.pendingImport`.
///
/// SwiftUI can't present a sheet from a view that is already presenting one, so a preview asked for
/// from inside a sheet (Setup & sharing) has to be shown by that sheet. The root view shows it the rest
/// of the time, and stands back while a sheet that hosts its own preview is open.
struct ImportPreviewHost: ViewModifier {
    /// False while the preview must wait (child mode, or a sheet above is hosting it instead).
    var isActive: Bool
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { isActive ? model.pendingImport : nil },
                set: { if $0 == nil { model.pendingImport = nil } })) { pending in
                ImportPreviewSheet(pending: pending)
            }
            .alert("This file couldn't be imported", isPresented: Binding(
                get: { isActive && model.importError != nil },
                set: { if !$0 { model.importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.importError ?? "")
            }
    }
}
