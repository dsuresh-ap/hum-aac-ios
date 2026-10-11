// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig
#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

/// Design tokens in one place, so the visual design pass only has to change this file.
///
/// Calm, muted colors. Protest and regulation tiles get the same saturation and weight as requests:
/// "no" is never shown as an error.
enum Theme {
    // Layout
    static let tileCorner: CGFloat = 22
    static let gridSpacing: CGFloat = 12
    static let gridPadding: CGFloat = 16
    static let topBarHeight: CGFloat = 68
    /// How far a tile's face sits above its edge. Pressing pushes the face down, like a soft physical key.
    static let keyDepth: CGFloat = 5
    static let pressAnimation = Animation.easeOut(duration: 0.15)

    // Surfaces: a cool "mist" so real photos and tile colors stand out (not cream, not white).
    static let background = Color.adaptive(light: 0xE9EDF0, dark: 0x161B20)
    static let ink = Color.adaptive(light: 0x26303A, dark: 0xEEF1F4)
    static let tileText = ink
    static let chrome = Color.adaptive(light: 0xDCE2E7, dark: 0x232A31)
    /// Parent mode band, so it's always clear you're editing.
    static let editBand = Color.adaptive(light: 0xD5E7E6, dark: 0x1F3536)

    /// Tile face colors by function. Muted, distinct in lightness as well as hue, and "no" (rosehip) is
    /// never alarm red: protest is communication, not an error.
    static func tileColor(function: TileFunction?, hex: String?) -> Color {
        if let hex, let value = UInt32(hex.dropFirst(), radix: 16) { return Color(hex: value) }
        let (light, dark) = palette(function)
        return .adaptive(light: light.face, dark: dark.face)
    }

    /// The darker edge under the face (the "key" side).
    static func tileEdge(function: TileFunction?, hex: String?) -> Color {
        if let hex, let value = UInt32(hex.dropFirst(), radix: 16) { return Color(hex: value).opacity(0.55) }
        let (light, dark) = palette(function)
        return .adaptive(light: light.edge, dark: dark.edge)
    }

    private static func palette(_ f: TileFunction?) -> (light: (face: UInt32, edge: UInt32), dark: (face: UInt32, edge: UInt32)) {
        switch f {
        case .request:    return ((0xCFE4C6, 0xA9C79C), (0x31452E, 0x22301F))  // moss
        case .protest:    return ((0xF2CBC2, 0xD9A497), (0x55332E, 0x3B2320))  // rosehip
        case .regulation: return ((0xDAD3F0, 0xB6AADB), (0x3D3757, 0x2A263D))  // lavender
        case .connection: return ((0xF6DCB4, 0xDDB985), (0x524329, 0x392F1C))  // apricot
        case .comment:    return ((0xC5DFEC, 0x99BFD3), (0x2D4352, 0x1F2F39))  // sky
        case .other, nil: return ((0xE4E3DF, 0xC3C1BB), (0x383B3F, 0x26292C))  // pebble
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// A color that follows Light/Dark mode.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        func make(_ hex: UInt32) -> PlatformColor {
            PlatformColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        #if canImport(UIKit)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? make(dark) : make(light) })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark) : make(light)
        })
        #endif
    }
}
