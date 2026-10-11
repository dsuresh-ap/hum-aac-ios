// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation

/// Finds the most natural voice on this device.
///
/// Apple's natural-sounding voices (Enhanced and Premium) aren't installed by default, and apps can't
/// download them. A parent downloads them once in system Settings. Until then only "compact" voices exist,
/// which sound robotic. Hum always uses the best one installed and upgrades automatically when a better
/// version appears. Voices from third-party voice apps installed on the device (iOS 17+ speech provider
/// extensions) appear here too.
enum VoiceCatalog {
    /// Voices for the device's language, best first. Novelty voices ("Bubbles", "Jester") are left out.
    static func voices(language: String = AVSpeechSynthesisVoice.currentLanguageCode()) -> [AVSpeechSynthesisVoice] {
        let prefix = String(language.prefix(2))
        let current = AVSpeechSynthesisVoice.currentLanguageCode()
        let systemDefault = AVSpeechSynthesisVoice(language: current)?.identifier
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { isBetter($0, $1, current: current, systemDefault: systemDefault) }
    }

    /// Premium > Enhanced > Standard, then the system's own default voice, then the device's exact
    /// locale (en-US over en-GB), then A→Z.
    private static func isBetter(_ a: AVSpeechSynthesisVoice, _ b: AVSpeechSynthesisVoice, current: String, systemDefault: String?) -> Bool {
        if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
        if (a.identifier == systemDefault) != (b.identifier == systemDefault) { return a.identifier == systemDefault }
        let aLocal = a.language == current, bLocal = b.language == current
        if aLocal != bLocal { return aLocal }
        return a.name < b.name
    }

    static func best(language: String = AVSpeechSynthesisVoice.currentLanguageCode()) -> AVSpeechSynthesisVoice? {
        voices(language: language).first
    }

    /// True when only robotic "compact" voices are installed for this language.
    static var onlyCompactVoicesInstalled: Bool {
        !voices().contains { $0.quality == .enhanced || $0.quality == .premium }
    }

    /// A better-quality version of the same voice, if the parent has since downloaded one
    /// (e.g. "Zoe" → "Zoe (Premium)").
    static func upgrade(for identifier: String) -> AVSpeechSynthesisVoice? {
        guard let current = AVSpeechSynthesisVoice(identifier: identifier) else { return nil }
        if current.voiceTraits.contains(.isPersonalVoice) { return nil }
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.name == current.name && $0.language == current.language && $0.quality.rawValue > current.quality.rawValue }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    static func qualityName(_ voice: AVSpeechSynthesisVoice) -> String {
        if voice.voiceTraits.contains(.isPersonalVoice) { return "Personal Voice" }
        switch voice.quality {
        case .premium: return "Premium, most natural"
        case .enhanced: return "Enhanced, natural"
        default: return "Standard"
        }
    }
}

/// Quick ways to shape any voice. "Younger" raises the pitch and slows down a little; it's an
/// approximation (Apple has no child voices). For a real child's voice, record tiles with a sibling.
enum VoiceStyle: String, CaseIterable, Sendable {
    case natural, younger, calm, custom

    var title: String {
        switch self {
        case .natural: "Natural"
        case .younger: "Younger"
        case .calm: "Calm"
        case .custom: "Custom"
        }
    }

    /// (rate 0...1, pitch 0.5...2)
    var values: (rate: Double, pitch: Double)? {
        switch self {
        case .natural: (0.5, 1.0)
        case .younger: (0.47, 1.35)
        case .calm: (0.42, 0.95)
        case .custom: nil
        }
    }

    static func matching(rate: Double, pitch: Double) -> VoiceStyle {
        allCases.first { style in
            guard let v = style.values else { return false }
            return abs(v.rate - rate) < 0.005 && abs(v.pitch - pitch) < 0.005
        } ?? .custom
    }
}
