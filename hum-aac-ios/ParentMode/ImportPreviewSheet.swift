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

    private var plan: MergePlanner.Plan { mode == .merge ? pending.merge : pending.replace }

    var body: some View {
        NavigationStack {
            Form {
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
                            Label { Text("\(tile.label): “\(tile.spokenText)”") } icon: { Image(systemName: "plus.circle.fill").foregroundStyle(.green) }
                        }
                        ForEach(changedTiles, id: \.id) { tile in
                            Label { Text("\(tile.label): “\(tile.spokenText)”") } icon: { Image(systemName: "pencil.circle.fill").foregroundStyle(.blue) }
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .merge ? "Merge" : "Replace…") {
                        if mode == .merge { apply() } else { confirmReplace = true }
                    }
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
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 460)
        #endif
    }

    private var allIncomingTiles: [HumTile] {
        plan.result.boards.flatMap(\.tiles) + plan.unplaced.map(\.tile)
    }
    private var newTiles: [HumTile] { allIncomingTiles.filter { plan.newTileIDs.contains($0.id) }.prefix(30).map { $0 } }
    private var changedTiles: [HumTile] { allIncomingTiles.filter { plan.changedTileIDs.contains($0.id) }.prefix(30).map { $0 } }

    private func apply() {
        do {
            try ImportService(model: model).apply(pending, mode: mode)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
