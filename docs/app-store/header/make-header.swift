// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0
//
// Renders the App Store header in Hum's style. Usage: swift header.swift <width> <height> <out.png>
import SwiftUI
import AppKit

func hex(_ v: UInt32) -> Color {
    Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

struct Tile: View {
    let emoji: String, label: String, face: UInt32, edge: UInt32, side: CGFloat
    var body: some View {
        let corner = side * 0.16
        VStack(spacing: side * 0.06) {
            Text(emoji).font(.system(size: side * 0.36))
            Text(label)
                .font(.system(size: side * 0.115, weight: .semibold, design: .rounded))
                .foregroundStyle(hex(0x26303A))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, side * 0.06)
        }
        .frame(width: side, height: side)
        .background(RoundedRectangle(cornerRadius: corner).fill(hex(face)))
        .background(RoundedRectangle(cornerRadius: corner).fill(hex(edge)).offset(y: side * 0.04))
    }
}

struct Header: View {
    let size: CGSize
    var body: some View {
        // Keep everything in the middle: the App Store crops the header differently on each device.
        let side = min(size.width * 0.105, size.height * 0.27)
        ZStack {
            hex(0xE9EDF0)
            VStack(spacing: side * 0.42) {
                Text("A voice in whole phrases")
                    .font(.system(size: side * 0.42, weight: .semibold, design: .serif))
                    .foregroundStyle(hex(0x26303A))
                HStack(spacing: side * 0.14) {
                    Tile(emoji: "👋", label: "Hi!", face: 0xF6DCB4, edge: 0xDDB985, side: side)
                    Tile(emoji: "🚀", label: "Let's go!", face: 0xCFE4C6, edge: 0xA9C79C, side: side)
                    Tile(emoji: "👀", label: "Look at that!", face: 0xC5DFEC, edge: 0x99BFD3, side: side)
                    Tile(emoji: "🙅", label: "No thank you", face: 0xF2CBC2, edge: 0xD9A497, side: side)
                    Tile(emoji: "🛋️", label: "I need a break", face: 0xDAD3F0, edge: 0xB6AADB, side: side)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

let args = CommandLine.arguments
let size = CGSize(width: Double(args[1])!, height: Double(args[2])!)
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Header(size: size))
    renderer.scale = 1
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        fatalError("render failed")
    }
    try! png.write(to: URL(fileURLWithPath: args[3]))
}
