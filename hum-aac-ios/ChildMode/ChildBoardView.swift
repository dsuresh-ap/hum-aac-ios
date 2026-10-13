// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig

/// The child's screen: a full-window grid of large tiles. A board taller than the window scrolls down.
///
/// The Home button stays in the top-leading corner and the parent lock in the top-trailing corner, on
/// every board, so the child's motor plan never changes.
struct ChildBoardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// An iPhone in landscape.
    private var shortScreen: Bool { verticalSizeClass == .compact }
    #else
    private let shortScreen = false
    #endif
    /// Tighter margins on iPhone so 4 columns stay close to the 88 pt minimum tile width.
    private var padding: CGFloat { sizeClass == .compact ? 8 : Theme.gridPadding }
    @State private var showFinder = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            // iPhone in landscape is short: the tiles get every row of height there.
            if model.settings.sentenceStrip && !shortScreen {
                SentenceStrip()
            }
            if model.settings.showHistory && !shortScreen {
                HistoryBox()
            }
            if let snapshot = model.snapshot {
                BoardGrid(snapshot: snapshot, spacing: sizeClass == .compact ? 8 : Theme.gridSpacing)
                    .padding(padding)
            } else {
                ContentUnavailableView("No board yet", systemImage: "square.grid.3x3",
                                       description: Text("A parent can add a board in edit mode."))
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $showFinder) {
            WordFinderView(purpose: .child) { model.startFinding($0) }
        }
        #if os(iOS)
        // The lock sits near the top edge, where iPadOS holds touches back for its own swipes, so the
        // 3-second hold started late and parents let go too early (BUGS.md, HUM-044). Hum's touches go
        // first; a second swipe still opens the system's.
        .defersSystemGestures(on: .top)
        .overlay {
            if model.settings.editGate == .twoFingerTripleTap {
                TwoFingerTripleTap { model.mode = .parent }
            }
        }
        #endif
    }

    private var topBar: some View {
        HStack {
            HomeButton(isHome: model.snapshot?.isHome ?? true) { model.goHome() }
                .overlay { if model.finderHint == .home { FinderGlow(cornerRadius: 16) } }
            // Back always has its own slot, so nothing shifts when it appears.
            BackButton(enabled: model.canGoBack) { model.goBack() }
                .overlay { if model.finderHint == .back { FinderGlow(cornerRadius: 16) } }
            Spacer()
            if let snapshot = model.snapshot, !snapshot.isHome {
                Text(snapshot.name)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    // One line that shrinks to fit, so a long name never pushes the buttons around.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.ink.opacity(0.6))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            if model.settings.showWordFinder {
                if let target = model.finderTarget {
                    // On a narrow iPhone only the ✕ shows, so the top bar never runs out of room.
                    FindingPill(target: target, showsTarget: sizeClass != .compact) { model.stopFinding() }
                }
            }
            // The finder sits right next to the lock (their touch areas meet but don't overlap).
            HStack(spacing: 0) {
                if model.settings.showWordFinder {
                    FinderButton { showFinder = true }
                }
                if model.settings.editGate == .holdLock {
                    EditGateButton { model.mode = .parent }
                } else {
                    // Keep the corner's size stable so nothing shifts when the gate type changes.
                    Color.clear.frame(width: 52, height: 52)
                }
            }
        }
        .padding(.horizontal, Theme.gridPadding)
        .frame(height: Theme.topBarHeight)
    }
}

/// Lays out the snapshot in a fixed rows × columns grid. Empty and hidden slots stay empty.
///
/// Tiles fill the window when they fit. A board taller than the window scrolls down (never sideways)
/// and opens at the top, so the first rows are always in the same place.
struct BoardGrid: View {
    let snapshot: BoardSnapshot
    var spacing: CGFloat = Theme.gridSpacing
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let layout = GridMetrics.layout(in: geo.size, rows: snapshot.rows, columns: snapshot.columns,
                                            spacing: spacing, canScroll: !snapshot.paged)
            if layout.scrolls {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        grid(layout)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    // The word finder's next tile may be below the fold: bring it into view.
                    .task(id: model.finderHint) {
                        if case .tile(let id) = model.finderHint {
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
                // A new board (or page) starts at the top. Sync updates to the same board keep the place.
                .id("\(snapshot.boardID)-\(snapshot.page)")
                .accessibilityIdentifier("boardScroll")
            } else {
                grid(layout)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.childBoardArea = $0 }
    }

    private func grid(_ layout: GridMetrics.Layout) -> some View {
        let settings = model.settings
        let hint = model.finderHint
        return VStack(spacing: spacing) {
            ForEach(0..<snapshot.rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<snapshot.columns, id: \.self) { column in
                        if let cell = snapshot.cells[row][column] {
                            TileView(
                                cell: cell,
                                showLabel: settings.showLabels,
                                labelOnTop: settings.labelPosition == .top,
                                // A touch on a scrolling board may be the start of a scroll: speak on lift.
                                speakOnTouchDown: settings.activation == .touchDown && !layout.scrolls,
                                inScrollView: layout.scrolls
                            ) { tapTime in
                                model.tap(cell, tapTime: tapTime)
                            }
                            .id(cell.id)
                            .frame(width: layout.tileWidth, height: layout.tileHeight)
                            .overlay { if hint == .tile(cell.id) { FinderGlow() } }
                            // The ring reaches past the tile: draw it over the tiles next to it.
                            .zIndex(hint == .tile(cell.id) ? 1 : 0)
                        } else {
                            Color.clear
                                .frame(width: layout.tileWidth, height: layout.tileHeight)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .zIndex(snapshot.cells[row].contains { $0.map { hint == .tile($0.id) } ?? false } ? 1 : 0)
            }
        }
    }
}

/// Opens the word finder. A small outlined circle like the lock, so it stays out of the child's way
/// and leaves the top bar room for the board name.
private struct FinderButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Theme.tileText.opacity(0.2), lineWidth: 3)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.tileText.opacity(0.6))
            }
            .frame(width: 36, height: 36)
            // A 44-point target, the smallest Apple recommends.
            .padding(4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Find a word")
        .accessibilityIdentifier("wordFinder")
    }
}

/// What the word finder is showing the way to, with a button to stop.
private struct FindingPill: View {
    let target: String
    var showsTarget = true
    let onStop: () -> Void

    var body: some View {
        Button(action: onStop) {
            HStack(spacing: 6) {
                if showsTarget { Text(target).lineLimit(1) }
                Image(systemName: "xmark.circle.fill")
            }
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(Theme.ink.opacity(0.85))
            .padding(.horizontal, 14).frame(height: 44)
            .background(Color.accentColor.opacity(0.25), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop finding \(target)")
        .accessibilityIdentifier("stopFinding")
    }
}

/// Back to the board this folder was opened from. Hidden (but still holding its place) on Home.
struct BackButton: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .frame(width: 72, height: 52)
                .background(Theme.chrome, in: .rect(cornerRadius: 16, style: .continuous))
                .background(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.chrome).brightness(-0.06).offset(y: 4)
                }
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
        .accessibilityHidden(!enabled)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("back")
    }
}

/// Large, fixed Home button. It is always in the same place; on Home it just looks quieter.
struct HomeButton: View {
    let isHome: Bool
    let action: () -> Void

    var body: some View {
        // Same "key" language as the tiles, so it reads as something to press. On Home it goes quiet
        // but never moves or disappears.
        Button(action: action) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.chrome.opacity(isHome ? 0.5 : 1))
                    .brightness(-0.06)
                Image(systemName: "house.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.ink.opacity(isHome ? 0.3 : 0.85))
                    .frame(width: 72, height: 52)
                    .background(Theme.chrome.opacity(isHome ? 0.5 : 1), in: .rect(cornerRadius: 16, style: .continuous))
            }
            .frame(width: 72, height: 56)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Home")
        .accessibilityIdentifier("home")
    }
}

/// Optional sentence strip (off by default, for NLA Stage 3+). Tapped tiles collect here; tap the strip
/// to hear them together. Tiles still speak on their own when tapped.
private struct SentenceStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.speakStrip()
            } label: {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(model.strip.enumerated()), id: \.offset) { _, cell in
                            Text(cell.label)
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.tileInk(function: cell.function, hex: cell.colorHex))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Theme.tileColor(function: cell.function, hex: cell.colorHex), in: .capsule)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(Theme.chrome, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Speak all: " + model.strip.map(\.spokenText).joined(separator: " "))

            Button {
                model.clearStrip()
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 30))
                    .foregroundStyle(Theme.tileText.opacity(0.5))
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear")
        }
        .padding(.horizontal, Theme.gridPadding)
        .padding(.bottom, 4)
    }
}

/// What was said recently, newest first. Tapping an entry says it again. Off by default.
/// A phrase as a sentence for VoiceOver: "Hi!" stays "Hi!", "All done" becomes "All done." (no "Hi!.").
enum HistoryBoxSentence {
    static func make(_ phrase: String) -> String {
        let trimmed = phrase.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return "" }
        return ".!?…".contains(last) ? trimmed : trimmed + "."
    }
}

private struct HistoryBox: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let recent = model.history.recent(12)
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink.opacity(0.45))
                .accessibilityHidden(true)
            if recent.isEmpty {
                Text("What your child says will show here.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Theme.ink.opacity(0.45))
                Spacer()
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                            Button {
                                model.replay(entry)
                            } label: {
                                Text(entry.spokenText)
                                    .font(.system(.body, design: .rounded, weight: index == 0 ? .semibold : .regular))
                                    .foregroundStyle(Theme.tileInk(function: entry.function, hex: entry.colorHex).opacity(index == 0 ? 1 : 0.7))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Theme.tileColor(function: entry.function, hex: entry.colorHex).opacity(index == 0 ? 1 : 0.6), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Said: \(HistoryBoxSentence.make(entry.spokenText)) Say it again.")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Theme.chrome.opacity(0.6), in: .rect(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, Theme.gridPadding)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recently said")
    }
}
