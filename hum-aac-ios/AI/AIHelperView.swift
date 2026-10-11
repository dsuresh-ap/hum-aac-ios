// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig

/// "Help me set up": the parent-only AI helper. Nothing changes until the parent previews and applies.
struct AIHelperView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Feature: String, CaseIterable { case describe = "Describe what you need", capture = "Add my child's phrases" }
    @State private var feature: Feature = .describe
    @State private var describeText = ""
    @State private var phrasesText = ""
    @State private var contextText = ""
    @State private var working = false
    @State private var proposal: AIHelper.Proposal?
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Use the AI helper", isOn: $settings.aiEnabled)
                    if settings.aiEnabled {
                        Picker("Where it runs", selection: $settings.aiUsePrivateCloud) {
                            Text("On this device").tag(false)
                            if case .available = AIHelper.availability(mode: .privateCloud) {
                                Text("Private Cloud Compute").tag(true)
                            }
                        }
                        if settings.aiUsePrivateCloud {
                            Text("This sends your text request to Apple's Private Cloud Compute. Apple does not store it.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Off until you turn it on. Only your words and your tiles' text are used, never photos or recordings. It only suggests tiles: you see a preview and choose whether to add them.")
                }

                if settings.aiEnabled {
                    if case .unavailable(let reason) = AIHelper.availability(mode: mode) {
                        Section { Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
                    } else {
                        Section {
                            Picker("What would you like?", selection: $feature) {
                                ForEach(Feature.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            switch feature {
                            case .describe:
                                TextField("e.g. My child loves trains and says “all aboard!” when she wants to go.", text: $describeText, axis: .vertical)
                                    .lineLimit(3...8)
                            case .capture:
                                TextField("One phrase per line, exactly as your child says it", text: $phrasesText, axis: .vertical)
                                    .lineLimit(3...10)
                                TextField("When does your child say these? (optional)", text: $contextText, axis: .vertical)
                                    .lineLimit(1...4)
                            }
                            Button {
                                Task { await run() }
                            } label: {
                                if working { ProgressView() } else { Label("Suggest tiles", systemImage: "sparkles") }
                            }
                            .disabled(working || inputIsEmpty)
                        }

                        if let proposal {
                            Section("Suggestions") {
                                if proposal.tiles.isEmpty {
                                    Text("No new tiles to suggest.").foregroundStyle(.secondary)
                                }
                                ForEach(Array(proposal.tiles.enumerated()), id: \.offset) { _, tile in
                                    VStack(alignment: .leading) {
                                        Text(tile.label).font(.headline)
                                        Text("“\(tile.spokenText)”").foregroundStyle(.secondary)
                                        if let board = tile.boardName { Text("Board: \(board)").font(.caption).foregroundStyle(.tertiary) }
                                    }
                                }
                                ForEach(proposal.notes, id: \.self) { note in
                                    Label(note, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                                }
                                if !proposal.tiles.isEmpty {
                                    Button("Preview and add…", systemImage: "eye") { preview(proposal) }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Help me set up")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("The helper couldn't finish", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private var mode: AIHelper.Mode { model.settings.aiUsePrivateCloud ? .privateCloud : .onDevice }

    private var inputIsEmpty: Bool {
        feature == .describe ? describeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : phrasesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func run() async {
        working = true
        defer { working = false }
        let existing = ConfigBridge.export(boards: model.store.boards()).document
        let task: AIHelper.Task = feature == .describe
            ? .describe(describeText)
            : .capture(phrases: phrasesText.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                       context: contextText)
        do {
            proposal = try await AIHelper.propose(task, mode: mode, existing: existing)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Please try again, or try a shorter request."
        }
    }

    /// Hands the checked tiles to the same import preview as a file. The parent taps Apply there.
    private func preview(_ proposal: AIHelper.Proposal) {
        let existing = ConfigBridge.export(boards: model.store.boards()).document
        let document = ProposalChecker.document(from: proposal.tiles, targetBoardID: model.editingBoardID, existing: existing)
        let issues = HumValidator.semanticIssues(in: document)
        if let error = issues.first(where: { $0.severity == .error }) {
            errorMessage = error.message
            return
        }
        let loaded = LoadedConfig(document: document, media: [:], warnings: issues)
        model.pendingImport = ImportService(model: model).prepare(loaded: loaded, fileName: "Suggestions from the AI helper")
        dismiss()
    }
}
