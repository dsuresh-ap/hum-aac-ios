// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0
//
// Draws the App Store product page header and search results assets in Hum's style.
// Usage: swift make-header.swift <universal|header|search> <out.png>
//
// The title and three tiles stay inside Apple's "art safe area" for each asset, so no device crops
// them. Faded tiles fill the rest of the canvas and can be cut off anywhere. The PNG has no alpha
// channel: run it through `ffmpeg -pix_fmt rgb24` (make-header.sh does this).
import SwiftUI
import AppKit

func hex(_ v: UInt32) -> Color {
    Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

/// Canvas size and art safe area of each asset (App Store Connect creative assets specifications).
let assets: [String: (size: CGSize, safe: CGRect)] = [
    "universal": (CGSize(width: 5244, height: 2950), CGRect(x: 1921, y: 660, width: 1402, height: 962)),
    "header": (CGSize(width: 3840, height: 1646), CGRect(x: 1097, y: 493, width: 1646, height: 661)),
    "search": (CGSize(width: 3840, height: 2560), CGRect(x: 836, y: 765, width: 2168, height: 1030)),
]

/// Tile colors (face, edge) from Hum's palette: apricot, moss, sky, rosehip, lavender.
let palette: [(UInt32, UInt32)] = [(0xF6DCB4, 0xDDB985), (0xCFE4C6, 0xA9C79C), (0xC5DFEC, 0x99BFD3),
                                   (0xF2CBC2, 0xD9A497), (0xDAD3F0, 0xB6AADB)]

struct Tile: View {
    let emoji: String, label: String, color: (UInt32, UInt32), side: CGFloat
    var body: some View {
        let corner = side * 0.16
        VStack(spacing: side * 0.06) {
            Text(emoji).font(.system(size: side * 0.36))
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: side * 0.115, weight: .semibold, design: .rounded))
                    .foregroundStyle(hex(0x26303A))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, side * 0.06)
            }
        }
        .frame(width: side, height: side)
        .background(RoundedRectangle(cornerRadius: corner).fill(hex(color.0)))
        .background(RoundedRectangle(cornerRadius: corner).fill(hex(color.1)).offset(y: side * 0.04))
    }
}

struct Artwork: View {
    let size: CGSize, safe: CGRect
    let background = ["👋", "🍎", "🧸", "🌳", "🙋", "🛋️", "🙉", "✋", "✅", "🧃", "🛝", "🎵", "🐶", "🚗", "🛁", "🌙",
                      "🤗", "😮", "😂", "🔁", "⬆️", "🙌", "🍪", "🚌"]
    var body: some View {
        // The three tiles fill most of the safe area's width; the title sits above them.
        let inner = safe.insetBy(dx: safe.width * 0.04, dy: safe.height * 0.06)
        let gap: CGFloat = 0.12
        let side = min(inner.width / (3 + 2 * gap), inner.height * 0.62)
        let step = side * (1 + gap)
        let titleSize = min(inner.width / 10.4, inner.height * 0.2)
        ZStack(alignment: .topLeading) {
            hex(0xE9EDF0)
            // Faded tiles on a grid across the whole canvas, leaving the safe area clear.
            let clear = safe.insetBy(dx: -side * 0.15, dy: -side * 0.15)
            let columns = Int((size.width / step).rounded(.up)) + 2, rows = Int((size.height / step).rounded(.up)) + 2
            let origin = CGPoint(x: safe.midX - step * CGFloat(columns / 2) - side / 2,
                                 y: safe.midY - step * CGFloat(rows / 2) - side / 2)
            ForEach(0..<rows, id: \.self) { row in
                ForEach(0..<columns, id: \.self) { column in
                    let frame = CGRect(x: origin.x + CGFloat(column) * step, y: origin.y + CGFloat(row) * step,
                                       width: side, height: side)
                    if !frame.intersects(clear) {
                        let i = row * 7 + column * 3
                        Tile(emoji: background[i % background.count], label: "", color: palette[i % palette.count], side: side)
                            .opacity(0.35)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
            }
            VStack(spacing: inner.height * 0.07) {
                Text("A voice in whole phrases")
                    .font(.system(size: titleSize, weight: .semibold, design: .serif))
                    .foregroundStyle(hex(0x26303A))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                HStack(spacing: side * gap) {
                    Tile(emoji: "🚀", label: "Let's go!", color: palette[1], side: side)
                    Tile(emoji: "👀", label: "Look at that!", color: palette[2], side: side)
                    Tile(emoji: "🙅", label: "No thank you", color: palette[3], side: side)
                }
            }
            .frame(width: inner.width, height: inner.height)
            .offset(x: inner.minX, y: inner.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }
}

let args = CommandLine.arguments
guard args.count == 3, let asset = assets[args[1]] else {
    print("Usage: swift make-header.swift <universal|header|search> <out.png>"); exit(1)
}
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Artwork(size: asset.size, safe: asset.safe))
    renderer.scale = 1
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        fatalError("render failed")
    }
    try! png.write(to: URL(fileURLWithPath: args[2]))
}
