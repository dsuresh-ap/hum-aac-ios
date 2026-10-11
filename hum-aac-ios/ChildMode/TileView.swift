// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// One tile in child mode.
///
/// It speaks on touch-down by default (fastest, and right for children who stim vocally). Every touch
/// speaks: no debounce and no rate limit. The press highlight is just view state, set *after* the sound
/// is queued, so drawing can never delay audio.
struct TileView: View {
    let cell: BoardSnapshot.Cell
    let showLabel: Bool
    let labelOnTop: Bool
    let speakOnTouchDown: Bool
    let onTap: (UInt64) -> Void

    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geo in
            // Soft physical key: a darker edge underneath, the face on top. Pressing pushes the face
            // down onto the edge. With Reduce Motion, the face stays put and only the highlight shows.
            let depth = pressed && !reduceMotion ? 1 : Theme.keyDepth
            let faceHeight = geo.size.height - Theme.keyDepth
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                    .fill(Theme.tileEdge(function: cell.function, hex: cell.colorHex))
                content(size: CGSize(width: geo.size.width, height: faceHeight))
                    .frame(width: geo.size.width, height: faceHeight)
                    .background(Theme.tileColor(function: cell.function, hex: cell.colorHex),
                                in: .rect(cornerRadius: Theme.tileCorner, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                            .fill(Color.white.opacity(pressed ? 0.28 : 0))
                    }
                    .overlay {
                        if contrast == .increased {
                            RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                                .strokeBorder(Theme.ink, lineWidth: 2.5)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if cell.linkedBoardID != nil { FolderCorner() }
                    }
                    .clipShape(.rect(cornerRadius: Theme.tileCorner, style: .continuous))
                    .offset(y: Theme.keyDepth - depth)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(.rect(cornerRadius: Theme.tileCorner, style: .continuous))
            .gesture(touchGesture(size: geo.size))
        }
        .accessibilityElement()
        .accessibilityLabel(cell.spokenText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(cell.linkedBoardID != nil ? Text("Opens a board") : Text(""))
        .accessibilityAction { onTap(mach_absolute_time()) }
        .accessibilityIdentifier("tile.\(cell.label)")
    }

    private func touchGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { _ in
                guard !pressed else { return }
                let now = mach_absolute_time()
                if speakOnTouchDown { onTap(now) }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.06)) { pressed = true }
            }
            .onEnded { value in
                if !speakOnTouchDown, CGRect(origin: .zero, size: size).contains(value.location) {
                    onTap(mach_absolute_time())
                }
                withAnimation(Theme.pressAnimation) { pressed = false }
            }
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        let labelFont = Font.system(size: max(14, min(size.width, size.height) * 0.13), weight: .semibold, design: .rounded)
        VStack(spacing: 4) {
            if showLabel && labelOnTop { label(labelFont) }
            picture(size: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showLabel && !labelOnTop { label(labelFont) }
        }
        .padding(size.width > 120 ? 10 : 6)
    }

    private func label(_ font: Font) -> some View {
        Text(cell.label)
            .font(font)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private func picture(size: CGSize) -> some View {
        if let image = cell.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: Theme.tileCorner * 0.6))
        } else if let symbol = cell.symbol, !symbol.isEmpty {
            Text(symbol)
                .font(.system(size: min(size.width, size.height) * 0.42))
                .minimumScaleFactor(0.3)
        } else {
            Color.clear
        }
    }
}

/// Small folder mark in the top-right corner of tiles that open another board.
private struct FolderCorner: View {
    var body: some View {
        // A folded corner: this tile also opens a board.
        Triangle()
            .fill(Theme.ink.opacity(0.18))
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
    }
}

nonisolated private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
