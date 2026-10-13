// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import HumConfig

/// Settings that belong to this device and never sync: voices differ per device, and network
/// features (iCloud, AI) must be switched on by a parent on each device.
///
/// Stored in UserDefaults. Values are written as they change; there is nothing to "save".
@Observable
final class DeviceSettings {
    enum EditGate: String, CaseIterable, Sendable { case holdLock, twoFingerTripleTap }

    @ObservationIgnored private let defaults: UserDefaults

    // Speech
    var voiceIdentifier: String? { didSet { defaults.set(voiceIdentifier, forKey: Keys.voice) } }
    /// AVSpeechUtterance scale: 0...1, 0.5 is normal.
    var rate: Double { didSet { defaults.set(rate, forKey: Keys.rate) } }
    /// 0.5...2, 1 is normal.
    var pitch: Double { didSet { defaults.set(pitch, forKey: Keys.pitch) } }
    var volume: Double { didSet { defaults.set(volume, forKey: Keys.volume) } }
    var retrigger: HumSettings.Retrigger { didSet { defaults.set(retrigger.rawValue, forKey: Keys.retrigger) } }
    var activation: HumSettings.Activation { didSet { defaults.set(activation.rawValue, forKey: Keys.activation) } }
    /// Off by default: some children dislike haptics. iPhone only.
    var haptics: Bool { didSet { defaults.set(haptics, forKey: Keys.haptics) } }

    // Display
    var showLabels: Bool { didSet { defaults.set(showLabels, forKey: Keys.showLabels) } }
    var labelPosition: HumSettings.LabelPosition { didSet { defaults.set(labelPosition.rawValue, forKey: Keys.labelPosition) } }
    /// Off by default (for NLA Stage 3+).
    var sentenceStrip: Bool { didSet { defaults.set(sentenceStrip, forKey: Keys.sentenceStrip) } }
    var appearance: HumSettings.Appearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    /// A small box in child mode showing what was said recently. Off by default (calm screen first).
    var showHistory: Bool { didSet { defaults.set(showHistory, forKey: Keys.showHistory) } }
    /// A magnifier in child mode that shows the way to a tile (the word finder). Off by default.
    var showWordFinder: Bool { didSet { defaults.set(showWordFinder, forKey: Keys.wordFinder) } }
    /// After a tile inside a folder speaks, go back to Home automatically. Off by default.
    var returnHomeAfterFolderTap: Bool { didSet { defaults.set(returnHomeAfterFolderTap, forKey: Keys.returnHome) } }
    /// Grid size for new boards.
    var newBoardRows: Int { didSet { defaults.set(newBoardRows, forKey: Keys.newRows) } }
    var newBoardColumns: Int { didSet { defaults.set(newBoardColumns, forKey: Keys.newColumns) } }

    // Parent
    var editGate: EditGate { didSet { defaults.set(editGate.rawValue, forKey: Keys.editGate) } }
    var hasCompletedSetup: Bool { didSet { defaults.set(hasCompletedSetup, forKey: Keys.setupDone) } }
    var hasSeenGuidedAccessTip: Bool { didSet { defaults.set(hasSeenGuidedAccessTip, forKey: Keys.guidedAccessTip) } }

    // Off until a parent turns them on (M4 / M5).
    var iCloudSyncEnabled: Bool { didSet { defaults.set(iCloudSyncEnabled, forKey: Keys.iCloud) } }
    var aiEnabled: Bool { didSet { defaults.set(aiEnabled, forKey: Keys.ai) } }
    /// false = on-device model (default when AI is on), true = Apple Private Cloud Compute.
    var aiUsePrivateCloud: Bool { didSet { defaults.set(aiUsePrivateCloud, forKey: Keys.aiPCC) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voiceIdentifier = defaults.string(forKey: Keys.voice)
        rate = defaults.object(forKey: Keys.rate) as? Double ?? 0.5
        pitch = defaults.object(forKey: Keys.pitch) as? Double ?? 1.0
        volume = defaults.object(forKey: Keys.volume) as? Double ?? 1.0
        retrigger = defaults.string(forKey: Keys.retrigger).flatMap(HumSettings.Retrigger.init) ?? .restart
        activation = defaults.string(forKey: Keys.activation).flatMap(HumSettings.Activation.init) ?? .touchDown
        haptics = defaults.bool(forKey: Keys.haptics)
        showLabels = defaults.object(forKey: Keys.showLabels) as? Bool ?? true
        labelPosition = defaults.string(forKey: Keys.labelPosition).flatMap(HumSettings.LabelPosition.init) ?? .bottom
        sentenceStrip = defaults.bool(forKey: Keys.sentenceStrip)
        appearance = defaults.string(forKey: Keys.appearance).flatMap(HumSettings.Appearance.init) ?? .system
        showHistory = defaults.bool(forKey: Keys.showHistory)
        showWordFinder = defaults.bool(forKey: Keys.wordFinder)
        returnHomeAfterFolderTap = defaults.bool(forKey: Keys.returnHome)
        newBoardRows = defaults.object(forKey: Keys.newRows) as? Int ?? 3
        newBoardColumns = defaults.object(forKey: Keys.newColumns) as? Int ?? 4
        editGate = defaults.string(forKey: Keys.editGate).flatMap(EditGate.init) ?? .holdLock
        hasCompletedSetup = defaults.bool(forKey: Keys.setupDone)
        hasSeenGuidedAccessTip = defaults.bool(forKey: Keys.guidedAccessTip)
        iCloudSyncEnabled = defaults.bool(forKey: Keys.iCloud)
        aiEnabled = defaults.bool(forKey: Keys.ai)
        aiUsePrivateCloud = defaults.bool(forKey: Keys.aiPCC)
    }

    /// Applies display/voice settings from an imported file. Never touches iCloud or AI.
    func apply(_ settings: HumSettings) {
        if let v = settings.voice {
            if let id = v.identifier { voiceIdentifier = id }
            if let r = v.rate { rate = min(max(r, 0), 1) }
            if let p = v.pitch { pitch = min(max(p, 0.5), 2) }
            if let vol = v.volume { volume = min(max(vol, 0), 1) }
        }
        if let s = settings.showLabels { showLabels = s }
        if let p = settings.labelPosition { labelPosition = p }
        if let s = settings.sentenceStrip { sentenceStrip = s }
        if let a = settings.appearance { appearance = a }
        if let r = settings.retrigger { retrigger = r }
        if let a = settings.activation { activation = a }
    }

    private enum Keys {
        static let voice = "voice.identifier", rate = "voice.rate", pitch = "voice.pitch", volume = "voice.volume"
        static let retrigger = "audio.retrigger", activation = "touch.activation", haptics = "touch.haptics"
        static let showLabels = "display.showLabels", labelPosition = "display.labelPosition"
        static let sentenceStrip = "display.sentenceStrip", appearance = "display.appearance"
        static let editGate = "parent.editGate", setupDone = "parent.setupDone", guidedAccessTip = "parent.guidedAccessTip"
        static let showHistory = "display.showHistory", returnHome = "nav.returnHome", wordFinder = "display.wordFinder"
        static let newRows = "grid.newRows", newColumns = "grid.newColumns"
        static let iCloud = "sync.iCloud", ai = "ai.enabled", aiPCC = "ai.privateCloud"
    }
}
