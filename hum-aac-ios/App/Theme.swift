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
    static let tileCorner: CGFloat = 18
    static let gridSpacing: CGFloat = 10
    static let gridPadding: CGFloat = 12
    static let topBarHeight: CGFloat = 64
    static let pressScale: CGFloat = 0.96
    static let pressAnimation = Animation.easeOut(duration: 0.15)

    static let background = Color.adaptive(light: 0xF6F4EF, dark: 0x1C1C1E)
    static let tileText = Color.adaptive(light: 0x2B2B2B, dark: 0xF2F2F2)
    static let chrome = Color.adaptive(light: 0xE9E6DF, dark: 0x2C2C2E)

    static func tileColor(function: TileFunction?, hex: String?) -> Color {
        if let hex, let value = UInt32(hex.dropFirst(), radix: 16) { return Color(hex: value) }
        switch function {
        case .protest: return .adaptive(light: 0xF3C9C4, dark: 0x5E3A37)
        case .regulation: return .adaptive(light: 0xD9CFF0, dark: 0x463F5C)
        case .request: return .adaptive(light: 0xCFE6CC, dark: 0x3A5238)
        case .connection: return .adaptive(light: 0xF6E2BF, dark: 0x5A4C30)
        case .comment: return .adaptive(light: 0xC8E0EE, dark: 0x34495A)
        case .other, nil: return .adaptive(light: 0xE6E3DD, dark: 0x3A3A3C)
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
