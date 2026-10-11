// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig
#if os(macOS)
import AppKit
#endif

/// Choose a tile's picture: an emoji (offline: suggestions from the tile's words, AAC-focused
/// categories, search, any emoji from the keyboard) or an AAC symbol from the online library.
struct EmojiPickerView: View {
    enum Source: String, CaseIterable { case emoji = "Emoji", symbols = "Symbols" }

    @Binding var selection: String
    let label: String
    let spokenText: String
    /// A chosen symbol's picture (already a tile-ready JPEG); it becomes the tile's image, like a photo.
    var onSymbol: ((Data) -> Void)? = nil
    @State var source: Source = .emoji

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var typed = ""
    @FocusState private var typing: Bool

    private var suggested: [String] { EmojiSuggester.suggestions(label: label, spokenText: spokenText, limit: 12) }
    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 8)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if onSymbol != nil {
                    Picker("Picture", selection: $source) {
                        ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding([.horizontal, .top])
                }
                switch source {
                case .emoji: emojiList
                case .symbols:
                    SymbolSearchView(initialQuery: label.isEmpty ? spokenText : label) { data in
                        onSymbol?(data)
                        dismiss()
                    }
                }
            }
            .navigationTitle(source == .emoji ? "Choose an emoji" : "Find a symbol")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !selection.isEmpty && source == .emoji {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("No emoji") { choose("") }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private var emojiList: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if search.isEmpty {
                        if !suggested.isEmpty { group("Suggested for this tile", suggested) }
                        ForEach(EmojiSuggester.categories) { category in
                            group(category.name, category.entries.map(\.emoji))
                        }
                    } else {
                        let found = EmojiSuggester.search(search)
                        if found.isEmpty {
                            Text("No match. Try another word, or type any emoji below.")
                                .foregroundStyle(.secondary)
                        } else {
                            group("Matches", found)
                        }
                    }
                    anyEmoji
                }
                .padding()
            }
            .searchable(text: $search, prompt: "Search, e.g. juice or train")
    }

    private func group(_ title: String, _ emoji: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(emoji, id: \.self) { item in
                    Button { choose(item) } label: {
                        Text(item)
                            .font(.system(size: 32))
                            .frame(width: 52, height: 52)
                            .background(item == selection ? Color.accentColor.opacity(0.25) : Theme.chrome,
                                        in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(keywords(for: item))
                }
            }
        }
    }

    /// Any emoji at all, from the system emoji keyboard or character viewer.
    private var anyEmoji: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Any other emoji").font(.headline)
            HStack {
                TextField("Type or paste an emoji", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
                    .frame(maxWidth: 220)
                    .onChange(of: typed) { _, new in
                        if let last = new.last, EmojiSuggester.isSingleEmoji(String(last)) { choose(String(last)) }
                    }
                #if os(macOS)
                Button("Show all emoji…", systemImage: "face.smiling") {
                    typing = true
                    NSApp.orderFrontCharacterPalette(nil)
                }
                #endif
            }
            #if os(iOS)
            Text("Tap the field, then the 🌐 or 😀 key on the keyboard.").font(.footnote).foregroundStyle(.secondary)
            #endif
        }
    }

    private func keywords(for emoji: String) -> String {
        EmojiSuggester.categories.flatMap(\.entries).first { $0.emoji == emoji }?.keywords.first ?? emoji
    }

    private func choose(_ emoji: String) {
        selection = emoji
        dismiss()
    }
}

/// Searches the online symbol libraries and shows the results as a grid. Searching is the only thing
/// that uses the network, and only the search word is sent.
private struct SymbolSearchView: View {
    let initialQuery: String
    let onPick: (Data) -> Void

    @AppStorage("symbolSource") private var source: SymbolLibrary.Source = .arasaac
    @State private var query = ""
    @State private var results: [SymbolLibrary.Symbol] = []
    @State private var searched = false
    @State private var working = false
    @State private var downloading: String?
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search symbols, e.g. swing", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { Task { await runSearch() } }
                Button("Search") { Task { await runSearch() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
            Picker("Symbol set", selection: $source) {
                ForEach(SymbolLibrary.Source.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: source) { Task { await runSearch() } }
            if let errorMessage {
                Label(errorMessage, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
            }
            ScrollView {
                if working && results.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if searched && results.isEmpty && errorMessage == nil {
                    Text("No symbols for “\(query)”. Try a simpler word, like “drink” instead of “let's have juice”, or the other symbol set.")
                        .foregroundStyle(.secondary).padding(.vertical)
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(results) { symbol in
                        Button {
                            Task { await pick(symbol) }
                        } label: {
                            VStack(spacing: 4) {
                                SymbolThumbnail(symbol: symbol)
                                    .frame(width: 88, height: 88)
                                    .overlay { if downloading == symbol.id { ProgressView() } }
                                Text(symbol.keyword).font(.caption).foregroundStyle(.black).lineLimit(1)
                            }
                            .padding(6)
                            .background(Color.white, in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .disabled(downloading != nil)
                        .accessibilityLabel("Symbol: \(symbol.keyword)")
                    }
                }
            }
            Text("Searching sends only your search word to \(source.name). The symbol you pick is saved in the tile, so it works offline. \(source.credit)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .task {
            guard query.isEmpty else { return }
            query = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            focused = true
            if !query.isEmpty { await runSearch() }
        }
    }

    private func runSearch() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        working = true
        errorMessage = nil
        defer { working = false; searched = true }
        do {
            results = try await SymbolLibrary.search(query, in: source)
            // A whole phrase rarely matches: fall back to its most picture-able word.
            if results.isEmpty, query.contains(" "), let word = EmojiSuggester.tokens(query).max(by: { $0.count < $1.count }) {
                results = try await SymbolLibrary.search(word, in: source)
            }
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }

    private func pick(_ symbol: SymbolLibrary.Symbol) async {
        downloading = symbol.id
        defer { downloading = nil }
        do {
            let raw = try await SymbolLibrary.download(symbol)
            guard let picture = await ImageProcessing.tileImageDataAllowingSVG(from: raw) else { throw SymbolLibrary.SearchError.failed }
            onPick(picture)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A symbol's preview. Loaded through the same image path as tiles, because Mulberry symbols are SVG.
private struct SymbolThumbnail: View {
    let symbol: SymbolLibrary.Symbol
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            } else {
                ProgressView()
            }
        }
        .task(id: symbol.id) {
            guard let data = try? await SymbolLibrary.download(symbol),
                  let jpeg = await ImageProcessing.tileImageDataAllowingSVG(from: data) else { failed = true; return }
            image = PlatformImage.thumbnail(jpeg, maxPixels: 200)
        }
    }
}
