// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig

/// The preview for suggested tiles (AI helper or pasted phrases): every tile, where it goes, and a
/// checkbox. Nothing changes until the parent taps Add. Existing tiles never move.
struct SuggestedTilesList: View {
    let tiles: [ProposedTile]
    @Binding var selected: Set<Int>
    /// Board name for tiles without their own folder.
    let targetName: String

    var body: some View {
        ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
            Button {
                if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected.contains(index) ? Color.accentColor : .secondary)
                    Text(tile.symbol ?? "▫️").font(.title2).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tile.label).font(.headline)
                        Text("“\(tile.spokenText)”").foregroundStyle(.secondary)
                        Text("Goes to \(tile.boardName ?? targetName)").font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected.contains(index) ? .isSelected : [])
        }
    }
}

/// "Paste phrases": add many tiles at once, one line per tile, with no AI. Each line stays whole.
struct PastePhrasesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var selected: Set<Int> = []
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    @FocusState private var editing: Bool

    private var targetName: String {
        model.editingBoardID.flatMap(model.fetchBoard)?.name ?? "Home"
    }

    /// The same checks as AI output: no praise phrases, no duplicates, short labels, an emoji each.
    private var checked: ProposalCheckResult {
        // No parent phrases: each line is already whole, and "All done" must not merge into "All done now".
        ProposalChecker.check(ProposalChecker.tiles(fromLines: text), parentPhrases: [],
                                     existing: ConfigBridge.export(boards: model.store.boards()).document)
    }

    var body: some View {
        let result = checked
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .focused($editing)
                        .frame(minHeight: 120)
                        .font(.body)
                        .accessibilityLabel("Phrases, one per line")
                        .onChange(of: text) { selected = Set(checked.tiles.indices) }
                } header: {
                    Text("One phrase per line")
                } footer: {
                    Text("Type or paste the phrases your child says, exactly as they say them. Each line becomes one tile, kept whole.")
                }

                if !result.tiles.isEmpty || !result.notes.isEmpty {
                    Section("Tiles to add") {
                        SuggestedTilesList(tiles: result.tiles, selected: $selected, targetName: targetName)
                        ForEach(result.notes, id: \.self) { note in
                            Label(note, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Paste phrases")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if text.isEmpty { dismiss() } else { confirmDiscard = true } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add \(selected.count)") { add(result.tiles) }
                        .disabled(selected.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .interactiveDismissDisabled(!text.isEmpty)
            .confirmationDialog("Discard these phrases?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("Couldn't add the tiles", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .onAppear { editing = true }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 520)
        #endif
    }

    private func add(_ tiles: [ProposedTile]) {
        let chosen = tiles.indices.filter(selected.contains).map { tiles[$0] }
        do {
            try ImportService(model: model).addSuggested(chosen, targetBoardID: model.editingBoardID, source: "Pasted phrases")
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
