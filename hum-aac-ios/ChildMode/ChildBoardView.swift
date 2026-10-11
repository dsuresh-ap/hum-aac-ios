// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig

/// The child's screen: a full-window grid of large tiles. No scrolling, ever.
///
/// The Home button stays in the top-leading corner and the parent lock in the top-trailing corner, on
/// every board, so the child's motor plan never changes.
struct ChildBoardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if model.settings.sentenceStrip {
                SentenceStrip()
            }
            if let snapshot = model.snapshot {
                BoardGrid(snapshot: snapshot)
                    .padding(Theme.gridPadding)
            } else {
                ContentUnavailableView("No board yet", systemImage: "square.grid.3x3",
                                       description: Text("A parent can add a board in edit mode."))
            }
        }
        .background(Theme.background)
        #if os(iOS)
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
            Spacer()
            if let snapshot = model.snapshot, !snapshot.isHome {
                Text(snapshot.name)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.tileText.opacity(0.7))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            if model.settings.editGate == .holdLock {
                EditGateButton { model.mode = .parent }
            } else {
                // Keep the corner's size stable so nothing shifts when the gate type changes.
                Color.clear.frame(width: 52, height: 52)
            }
        }
        .padding(.horizontal, Theme.gridPadding)
        .frame(height: Theme.topBarHeight)
    }
}

/// Lays out the snapshot in a fixed rows × columns grid. Empty and hidden slots stay empty.
struct BoardGrid: View {
    let snapshot: BoardSnapshot
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        GeometryReader { geo in
            let spacing = Theme.gridSpacing
            let width = (geo.size.width - spacing * CGFloat(snapshot.columns - 1)) / CGFloat(snapshot.columns)
            let height = (geo.size.height - spacing * CGFloat(snapshot.rows - 1)) / CGFloat(snapshot.rows)
            VStack(spacing: spacing) {
                ForEach(0..<snapshot.rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<snapshot.columns, id: \.self) { column in
                            if let cell = snapshot.cells[row][column] {
                                TileView(
                                    cell: cell,
                                    showLabel: settings.showLabels,
                                    labelOnTop: settings.labelPosition == .top,
                                    speakOnTouchDown: settings.activation == .touchDown
                                ) { tapTime in
                                    model.tap(cell, tapTime: tapTime)
                                }
                                .id(cell.id)
                                .frame(width: max(width, 0), height: max(height, 0))
                            } else {
                                Color.clear
                                    .frame(width: max(width, 0), height: max(height, 0))
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Large, fixed Home button. It is always in the same place; on Home it just looks quieter.
struct HomeButton: View {
    let isHome: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "house.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.tileText.opacity(isHome ? 0.35 : 0.85))
                .frame(width: 64, height: 52)
                .background(Theme.chrome, in: .rect(cornerRadius: 14))
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
