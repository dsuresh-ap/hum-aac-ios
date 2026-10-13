// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Look up a tile or folder by its words. Used by the child's word finder (results light up the way,
/// they never speak) and by Find in the editor (results open the board).
struct WordFinderView: View {
    enum Purpose { case child, editor }

    let purpose: Purpose
    let onPick: (WordFinder.Result) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var finder: WordFinder?
    @State private var query = ""
    @State private var results: [WordFinder.Result] = []
    /// The query `results` belong to, so "Nothing found" never flashes while a search is still running.
    @State private var searched = ""
    @FocusState private var focused: Bool

    private var exact: [WordFinder.Result] { results.filter { !$0.related } }
    private var related: [WordFinder.Result] { results.filter(\.related) }
    private var big: Bool { purpose == .child }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(purpose == .child ? "What are you looking for?" : "Find a tile or folder",
                              text: $query)
                        .font(big ? .title2 : .body)
                        .focused($focused)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .submitLabel(.search)
                        .accessibilityIdentifier("finderField")
                }
                if !exact.isEmpty {
                    Section { ForEach(exact) { row($0) } }
                }
                if !related.isEmpty {
                    Section {
                        ForEach(related) { row($0) }
                    } header: {
                        Text("Might be related")
                    }
                }
                if results.isEmpty && !WordFinder.normalized(query).isEmpty && searched == query {
                    Text("Nothing found for “\(query)”.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(purpose == .child ? "Find" : "Find a tile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("finderClose")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
        .onAppear {
            finder = WordFinder(boards: model.store.boards())
            focused = true
        }
        .task(id: query) {
            guard let finder else { return }
            // A short pause so related matches aren't worked out for every letter typed.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let text = query
            let found = await Task.detached(priority: .userInitiated) { finder.search(text) }.value
            guard !Task.isCancelled else { return }
            // The child can only follow a way that starts at Home.
            results = purpose == .child ? found.filter { $0.route != nil } : found
            searched = text
        }
    }

    private func row(_ result: WordFinder.Result) -> some View {
        Button {
            onPick(result)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Group {
                    if result.kind == .board {
                        Image(systemName: "folder.fill").foregroundStyle(.secondary)
                    } else if let symbol = result.symbol, !symbol.isEmpty {
                        Text(symbol)
                    } else {
                        Image(systemName: "square.fill").foregroundStyle(.tertiary)
                    }
                }
                .font(big ? .largeTitle : .title2)
                .frame(width: big ? 52 : 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.label).font(big ? .title2.weight(.semibold) : .body.weight(.semibold))
                    if result.kind == .tile, !result.spokenText.isEmpty,
                       WordFinder.normalized(result.spokenText) != WordFinder.normalized(result.label) {
                        Text("“\(result.spokenText)”").font(big ? .body : .subheadline).foregroundStyle(.secondary)
                    }
                    Text(result.route == nil ? "\(result.pathText) (not in a folder on Home)" : result.pathText)
                        .font(big ? .callout : .caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, big ? 6 : 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(purpose == .child ? "Lights up the way to it" : "Opens its board")
    }
}

/// The glow on the next thing to press for the word finder: a thick yellow ring with a dark edge, so it
/// shows on white, teal and dark tiles alike. It sits just outside the tile and gently grows and shrinks
/// (still with Reduce Motion). It never blocks a touch.
struct FinderGlow: View {
    var cornerRadius: CGFloat = Theme.tileCorner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    static let color = Color(red: 1, green: 0.82, blue: 0.1)
    private let outset: CGFloat = 5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius + outset, style: .continuous)
        ZStack {
            shape.strokeBorder(Self.color, lineWidth: 7)
            // A thin dark edge inside the yellow, so it stands out on light tiles too.
            shape.inset(by: 7).strokeBorder(Color.black.opacity(0.6), lineWidth: 2)
        }
        .padding(-outset)
        .shadow(color: Self.color.opacity(pulse ? 0.9 : 0.5), radius: pulse ? 16 : 8)
        .scaleEffect(reduceMotion ? 1 : (pulse ? 1.04 : 1))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
