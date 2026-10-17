// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig

/// "Help me set up": the parent-only AI helper. Three steps on one page:
/// 1. tell it about your child, 2. see the suggested tiles, 3. tick the ones you want and add them.
/// Nothing changes until the parent taps Add.
struct AIHelperView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Feature: CaseIterable {
        case describe, capture

        var title: String {
            switch self {
            case .describe: String(localized: "Describe your child")
            case .capture: String(localized: "Paste their phrases")
            }
        }
    }
    enum Field: Hashable { case describe, phrases, context }

    @State private var feature: Feature = .describe
    @State private var describeText = ""
    @State private var phrasesText = ""
    @State private var contextText = ""
    @State private var working = false
    @State private var proposal: AIHelper.Proposal?
    @State private var selected: Set<Int> = []
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                if !settings.aiEnabled {
                    introSection
                } else if case .unavailable(let reason) = AIHelper.availability(mode: mode) {
                    Section { Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
                    privacySection
                } else {
                    askSection
                    if let proposal { suggestionsSection(proposal) }
                    privacySection
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Help me set up")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // "Close", not "Done": Return must never close this page while the parent is typing.
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .alert("The helper couldn't finish", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .onAppear { focusInput() }
            .onChange(of: feature) { focusInput() }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 600)
        #endif
    }

    // MARK: Sections

    /// Shown while the helper is off: what it does, what it uses, and one button to turn it on.
    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Label("Get tile ideas from what your child says", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))
                Text("Tell the helper about your child, or paste phrases they say. It suggests whole-phrase tiles, and you choose which ones to add.")
                VStack(alignment: .leading, spacing: 8) {
                    Label("Only your words and your tiles' text are used. Never photos or recordings.", systemImage: "text.bubble")
                    Label("Runs on this device by default.", systemImage: "lock")
                    Label("It only suggests. Nothing changes until you tap Add.", systemImage: "hand.tap")
                }
                .fixedSize(horizontal: false, vertical: true)  // whole sentences, never "…are us…"
                .font(.callout)
                .foregroundStyle(.secondary)
                Button("Turn on the helper") {
                    model.settings.aiEnabled = true
                    focusInput()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("turnOnAI")
            }
            .padding(.vertical, 6)
        }
    }

    private var askSection: some View {
        Section {
            Picker("What would you like to do?", selection: $feature) {
                ForEach(Feature.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch feature {
            case .describe:
                TextField("e.g. My child loves trains and says “all aboard!” when they want to go.", text: $describeText, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($focus, equals: .describe)
            case .capture:
                ZStack(alignment: .topLeading) {
                    if phrasesText.isEmpty {
                        Text("One phrase per line, exactly as your child says it")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $phrasesText)
                        .focused($focus, equals: .phrases)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                }
                TextField("When does your child say these? (optional)", text: $contextText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focus, equals: .context)
            }
            HStack {
                Button {
                    Task { await run() }
                } label: {
                    Label(proposal == nil ? "Suggest tiles" : "Suggest again", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                // Return (outside the phrase list) or ⌘Return suggests.
                .keyboardShortcut(.defaultAction)
                .disabled(working || inputIsEmpty)
                .background {
                    Button("", action: { Task { await run() } })
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(working || inputIsEmpty)
                        .hidden()
                }
                if working {
                    ProgressView().controlSize(.small)
                    Text("Thinking… this can take a few seconds.").font(.callout).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("1. Tell the helper")
        } footer: {
            Text(feature == .describe
                 ? "Put the phrases your child really says in quotes, so they're kept exactly."
                 : "Each line becomes one tile, kept whole. Don't need suggestions? Use Add → Paste phrases instead.")
        }
    }

    private func suggestionsSection(_ proposal: AIHelper.Proposal) -> some View {
        Section {
            if proposal.tiles.isEmpty {
                Text("No new tiles to suggest. Try describing it another way.").foregroundStyle(.secondary)
            }
            SuggestedTilesList(tiles: proposal.tiles, selected: $selected, targetName: targetName)
            ForEach(proposal.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }
            if !proposal.tiles.isEmpty {
                Button {
                    add(proposal)
                } label: {
                    Label(selected.isEmpty ? "Choose tiles to add" : "Add \(selected.count) tiles", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("addSuggestions")
            }
        } header: {
            Text("2. Choose tiles to add")
        } footer: {
            Text("New tiles go in empty spots. Nothing already on your boards moves. You can undo.")
        }
    }

    /// Where it runs, the Private Cloud Compute note and quota, and turning the helper off.
    private var privacySection: some View {
        @Bindable var settings = model.settings
        return Section {
            Picker("Where it runs", selection: $settings.aiUsePrivateCloud) {
                Text("On this device").tag(false)
                if case .available = AIHelper.availability(mode: .privateCloud) {
                    Text("Private Cloud Compute").tag(true)
                }
            }
            if settings.aiUsePrivateCloud {
                Text("Your words are sent to Apple's Private Cloud Compute servers. Apple doesn't keep them.")
                    .font(.footnote).foregroundStyle(.secondary)
                quotaStatus
            }
            Toggle("Use the AI helper", isOn: $settings.aiEnabled)
        } header: {
            Text("Privacy")
        } footer: {
            // Shown for both "On this device" and Private Cloud Compute.
            VStack(alignment: .leading, spacing: 4) {
                Text("Only your words and your tiles' text are used, never photos or recordings.")
                Text("Suggestions come from AI and can be wrong. Nothing is added until you choose it.")
                    .accessibilityIdentifier("ai.mayBeWrong")
            }
        }
    }

    /// Today's Private Cloud Compute allowance, shown before it runs out rather than as a surprise.
    @ViewBuilder
    private var quotaStatus: some View {
        if let quota = AIHelper.quotaInfo(), quota.level != .fine {
            VStack(alignment: .leading, spacing: 6) {
                Label(Self.quotaText(quota),
                      systemImage: quota.level == .reached ? "gauge.with.dots.needle.100percent" : "gauge.with.dots.needle.67percent")
                    .font(.footnote)
                if quota.canShowOptions {
                    Button("Show options") { AIHelper.showQuotaOptions() }
                        .font(.footnote)
                }
            }
        }
    }

    private static func quotaText(_ quota: AIHelper.QuotaInfo) -> String {
        guard quota.level == .reached else { return String(localized: "You're close to today's Private Cloud Compute limit.") }
        if let reset = quota.resetDate {
            return String(localized: "Today's Private Cloud Compute requests are used up. They refresh \(reset.formatted(.relative(presentation: .named))). “On this device” still works.")
        }
        return String(localized: "Today's Private Cloud Compute requests are used up. “On this device” still works.")
    }

    // MARK: Actions

    private var mode: AIHelper.Mode { model.settings.aiUsePrivateCloud ? .privateCloud : .onDevice }

    private var targetName: String { model.editingBoardID.flatMap(model.fetchBoard)?.name ?? String(localized: "Home") }

    private var inputIsEmpty: Bool {
        feature == .describe ? describeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : phrasesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func focusInput() {
        DispatchQueue.main.async { focus = feature == .describe ? .describe : .phrases }
    }

    private func run() async {
        guard !working, !inputIsEmpty else { return }
        working = true
        defer { working = false }
        let existing = ConfigBridge.export(boards: model.store.boards()).document
        let task: AIHelper.Task = feature == .describe
            ? .describe(describeText)
            : .capture(phrases: phrasesText.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                       context: contextText)
        do {
            let result = try await AIHelper.propose(task, mode: mode, existing: existing)
            proposal = result
            selected = Set(result.tiles.indices)
        } catch let error as AIHelper.AIError {
            if case .quotaReached = error { model.settings.aiUsePrivateCloud = false }  // switch to on-device for next time
            errorMessage = error.errorDescription
        } catch {
            errorMessage = AIHelper.AIError.other.errorDescription
        }
    }

    /// The list above is the preview; Add runs the same Merge as a file import.
    private func add(_ proposal: AIHelper.Proposal) {
        let chosen = proposal.tiles.indices.filter(selected.contains).map { proposal.tiles[$0] }
        do {
            try ImportService(model: model).addSuggested(chosen, targetBoardID: model.editingBoardID, source: String(localized: "Suggestions from the AI helper"))
            dismiss()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}
