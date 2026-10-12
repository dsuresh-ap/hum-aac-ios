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
                        if cell.linkedBoardID != nil { FolderCorner(ink: ink) }
                    }
                    .clipShape(.rect(cornerRadius: Theme.tileCorner, style: .continuous))
                    .offset(y: Theme.keyDepth - depth)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(.rect(cornerRadius: Theme.tileCorner, style: .continuous))
            .gesture(touchGesture(size: geo.size))
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(cell.linkedBoardID != nil ? Text("Opens a board") : Text(""))
        .accessibilityAction { onTap(mach_absolute_time()) }
        .accessibilityIdentifier("tile.\(cell.label)")
    }

    /// What VoiceOver reads: the phrase, or for a silent tile its label (and "folder" only if it opens one).
    private var accessibilityText: String {
        if !cell.spokenText.isEmpty { return cell.spokenText }
        return cell.linkedBoardID != nil ? "\(cell.label), folder" : cell.label
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
                withAnimation(reduceMotion ? nil : Theme.pressAnimation) { pressed = false }
            }
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        let padding: CGFloat = size.width > 120 ? 10 : 6
        if TileShape.isWide(size) {
            wideContent(size: size)
        } else {
            let label = TileLabel(text: cell.label, fontSize: max(14, min(size.width, size.height) * 0.13),
                                  width: size.width - padding * 2)
                .foregroundStyle(ink)
            VStack(spacing: 4) {
                if showLabel && labelOnTop { label }
                picture(size: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showLabel && !labelOnTop { label }
            }
            .padding(padding)
        }
    }

    /// A wide, short tile (an iPhone page in landscape): the picture sits beside the label instead of
    /// above it, so it keeps a usable size. The tile stays in the same spot; only its inside changes.
    @ViewBuilder
    private func wideContent(size: CGSize) -> some View {
        // Thin padding above and below: on an iPhone in landscape a row is only ~32 pt tall, and the
        // picture should get nearly all of it.
        let vertical = min(6, size.height * 0.08)
        let side = max(size.height - vertical * 2, 0)
        let hasPicture = cell.image != nil || !(cell.symbol ?? "").isEmpty
        HStack(spacing: 8) {
            if hasPicture {
                picture(size: CGSize(width: side * 2.1, height: side * 2.1))  // emoji at ~0.9 of the side
                    .frame(width: side, height: side)
            }
            if showLabel {
                TileLabel(text: cell.label, fontSize: max(14, min(size.height * 0.4, size.width * 0.09)),
                          width: size.width - 20 - (hasPicture ? side + 8 : 0))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ink: Color { Theme.tileInk(function: cell.function, hex: cell.colorHex) }

    @ViewBuilder
    private func picture(size: CGSize) -> some View {
        if let image = cell.image {
            // Fit, not fill: the whole picture shows (a cropped symbol can lose its meaning), and a
            // big picture can never push the label out of the tile.
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: Theme.tileCorner * 0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let symbol = cell.symbol, !symbol.isEmpty {
            Text(symbol)
                .font(.system(size: min(size.width, size.height) * 0.42))
                .minimumScaleFactor(0.3)
        } else {
            Color.clear
        }
    }
}

/// Tile shapes that need their own layout inside.
enum TileShape {
    /// Much wider than tall (an iPhone page in landscape, or a wide grid): picture beside the label.
    static func isWide(_ size: CGSize) -> Bool { size.width >= size.height * 1.8 }
}

/// A tile's label. It shrinks a long word to fit instead of breaking it ("Clothin/g", BUGS.md HUM-043):
/// the font gets small enough for the longest word to fit on one line, and a one-word label stays on one line.
struct TileLabel: View {
    let text: String
    let fontSize: CGFloat
    /// The width the label can use.
    let width: CGFloat

    var body: some View {
        let words = text.split(whereSeparator: \.isWhitespace)
        let longest = words.map(\.count).max() ?? 0
        // Rounded semibold letters are about 0.6 of the font size wide.
        let fitting = longest > 0 ? max(1, width) / (CGFloat(longest) * 0.62) : fontSize
        Text(text)
            .font(.system(size: max(9, min(fontSize, fitting)), weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(words.count <= 1 ? 1 : 2)
            .minimumScaleFactor(0.6)
            .allowsTightening(true)
    }
}

/// Small folder mark in the top-right corner of tiles that open another board.
private struct FolderCorner: View {
    var ink = Theme.ink

    var body: some View {
        // A folded corner with a folder mark: this tile opens another board.
        ZStack(alignment: .topTrailing) {
            Triangle()
                .fill(ink.opacity(0.16))
                .frame(width: 44, height: 44)
            Image(systemName: "folder.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ink.opacity(0.6))
                .padding(7)
        }
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

#if DEBUG
/// A square picture (like Image Playground's) on wide and tall tiles: it must fit, and the label must show.
#Preview("Pictures fit their tiles") {
    let picture: CGImage? = {
        let context = CGContext(data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        context?.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context?.fillEllipse(in: CGRect(x: 60, y: 60, width: 280, height: 280))
        return context?.makeImage()
    }()
    let cell = { (label: String, folder: Bool) in
        BoardSnapshot.Cell(id: UUID(), label: label, spokenText: "Let's eat!", function: nil, colorHex: nil,
                           symbol: nil, image: picture, linkedBoardID: folder ? UUID() : nil, linkedBoardExists: folder,
                           recordingKey: nil)
    }
    HStack(spacing: 12) {
        TileView(cell: cell("Food", true), showLabel: true, labelOnTop: false, speakOnTouchDown: true) { _ in }
            .frame(width: 260, height: 150)
        TileView(cell: cell("snack", false), showLabel: true, labelOnTop: false, speakOnTouchDown: true) { _ in }
            .frame(width: 130, height: 200)
    }
    .padding()
    .background(Theme.background)
}
#endif
