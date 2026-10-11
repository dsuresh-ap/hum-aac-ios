// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AVFoundation
import HumConfig

/// Parent settings: voice, speech behavior, display, and the grown-up lock.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var personalVoiceStatus = ""

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                if VoiceCatalog.onlyCompactVoicesInstalled {
                    Section {
                        NaturalVoicesCard()
                    }
                }

                Section {
                    Picker("Style", selection: Binding(
                        get: { VoiceStyle.matching(rate: settings.rate, pitch: settings.pitch) },
                        set: { style in
                            if let v = style.values {
                                settings.rate = v.rate
                                settings.pitch = v.pitch
                                voiceChanged()
                                model.speech.speak("Let's go to the park!")
                            }
                        })) {
                        ForEach(VoiceStyle.allCases.filter { $0 != .custom || VoiceStyle.matching(rate: settings.rate, pitch: settings.pitch) == .custom }, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How it sounds")
                } footer: {
                    Text("“Younger” makes any voice higher and a little slower. Apple doesn't include children's voices; for a real child's voice, ask an older sibling or cousin to record tiles (edit a tile → Say it in your own voice).")
                }

                Section {
                    ForEach(voices, id: \.identifier) { voice in
                        VoiceRow(voice: voice, isSelected: voice.identifier == currentVoiceID) {
                            settings.voiceIdentifier = voice.identifier
                            voiceChanged()
                        }
                    }
                    Button("Use my own voice (Personal Voice)…", systemImage: "person.wave.2") { requestPersonalVoice() }
                    if !personalVoiceStatus.isEmpty {
                        Text(personalVoiceStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    Text("Best voices are listed first. Voices from voice apps you install on this device show up here too.")
                }

                Section("Fine-tune") {
                    LabeledContent("Speed") {
                        Slider(value: $settings.rate, in: 0.2...0.8, onEditingChanged: { if !$0 { voiceChanged() } })
                    }
                    LabeledContent("Pitch") {
                        Slider(value: $settings.pitch, in: 0.6...1.6, onEditingChanged: { if !$0 { voiceChanged() } })
                    }
                    LabeledContent("Volume") {
                        Slider(value: $settings.volume, in: 0.2...1, onEditingChanged: { if !$0 { voiceChanged() } })
                    }
                    Button("Play a sample", systemImage: "play.circle") { model.speech.speak("Let's go to the park!") }
                }

                Section {
                    Picker("When a tile is tapped while talking", selection: $settings.retrigger) {
                        Text("Start the new tap right away").tag(HumSettings.Retrigger.restart)
                        Text("Let speech finish first").tag(HumSettings.Retrigger.finish)
                        Text("Play both together").tag(HumSettings.Retrigger.overlap)
                    }
                    .onChange(of: settings.retrigger) { model.applySpeechSettings() }
                    Picker("Speak when the finger", selection: $settings.activation) {
                        Text("Touches the tile (fastest)").tag(HumSettings.Activation.touchDown)
                        Text("Lifts off the tile").tag(HumSettings.Activation.touchUp)
                    }
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        Toggle("Light vibration on tap", isOn: $settings.haptics)
                    }
                    #endif
                } header: {
                    Text("Tapping")
                } footer: {
                    Text("Every tap always makes a sound, even very fast repeated taps. Repeated tapping is communication too.")
                }

                Section {
                    Toggle("Show labels", isOn: $settings.showLabels)
                    Picker("Label position", selection: $settings.labelPosition) {
                        Text("Below the picture").tag(HumSettings.LabelPosition.bottom)
                        Text("Above the picture").tag(HumSettings.LabelPosition.top)
                    }
                    .disabled(!settings.showLabels)
                    Toggle("Sentence strip", isOn: $settings.sentenceStrip)
                    Toggle("History box (what was said recently)", isOn: $settings.showHistory)
                    Picker("Appearance", selection: $settings.appearance) {
                        Text("Match this device").tag(HumSettings.Appearance.system)
                        Text("Light").tag(HumSettings.Appearance.light)
                        Text("Dark").tag(HumSettings.Appearance.dark)
                    }
                } header: {
                    Text("Tiles")
                } footer: {
                    Text("The sentence strip collects tapped tiles so your child can play them together; it's for later stages of language. The history box shows what was said recently, so you can catch up if you missed it. Both are off at first, and each tile always speaks on its own.")
                }

                Section {
                    Toggle("Go back to Home after a tile in a folder speaks", isOn: $settings.returnHomeAfterFolderTap)
                    LabeledContent("Size for new boards") {
                        HStack(spacing: 8) {
                            GridPreview(rows: settings.newBoardRows, columns: settings.newBoardColumns).frame(width: 22, height: 22)
                            Text("\(settings.newBoardRows) × \(settings.newBoardColumns)").monospacedDigit()
                        }
                    }
                    Stepper("Rows: \(settings.newBoardRows)", value: $settings.newBoardRows, in: 1...8)
                    Stepper("Columns: \(settings.newBoardColumns)", value: $settings.newBoardColumns, in: 1...8)
                } header: {
                    Text("Folders and boards")
                } footer: {
                    Text("To change how many tiles an existing board shows, open it in edit mode and tap the grid size at the top right.")
                }

                Section {
                    Picker("To open grown-up settings", selection: $settings.editGate) {
                        Text("Press and hold the lock (3 seconds)").tag(DeviceSettings.EditGate.holdLock)
                        #if os(iOS)
                        Text("Two-finger triple-tap").tag(DeviceSettings.EditGate.twoFingerTripleTap)
                        #endif
                    }
                } header: {
                    Text("Grown-up lock")
                } footer: {
                    Text("For a full lock-down on iPad or iPhone, use Guided Access: Settings → Accessibility → Guided Access.")
                }

                Section {
                    Text(SymbolLibrary.credits).font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Credits")
                }

                Section("For developers") {
                    NavigationLink("Tap-to-sound latency") { DeveloperLatencyView() }
                        .accessibilityIdentifier("developerLatency")
                    LabeledContent("AI helper (on this device)") {
                        Text(aiStatus(.onDevice)).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("AI helper (Private Cloud Compute)") {
                        Text(aiStatus(.privateCloud)).multilineTextAlignment(.trailing)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(macOS)
            .navigationSubtitle("Changes save as you make them")
            #endif
            .safeAreaInset(edge: .bottom) {
                #if os(iOS)
                Text("Changes save as you make them.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(.bar)
                #endif
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear(perform: loadVoices)
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }

    private var currentVoiceID: String { model.speech.voice.identifier }

    private func aiStatus(_ mode: AIHelper.Mode) -> String {
        switch AIHelper.availability(mode: mode) {
        case .available: return "Available"
        case .unavailable(let reason): return reason
        }
    }

    /// Voices for the device's language, best quality first.
    private func loadVoices() {
        voices = VoiceCatalog.voices()
    }

    private func voiceChanged() {
        model.applySpeechSettings()
        model.rebuildSnapshot()  // re-renders the current board with the new voice
    }

    private func requestPersonalVoice() {
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { @Sendable status in
            Task { @MainActor in
                switch status {
                case .authorized:
                    personalVoiceStatus = "Personal Voice is allowed. Your voice is now in the list."
                    loadVoices()
                    if let mine = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.voiceTraits.contains(.isPersonalVoice) }) {
                        model.settings.voiceIdentifier = mine.identifier
                        voiceChanged()
                    }
                case .denied:
                    personalVoiceStatus = "Personal Voice was not allowed. You can change this in Settings → Accessibility → Personal Voice."
                case .unsupported:
                    personalVoiceStatus = "This device doesn't support Personal Voice."
                default:
                    personalVoiceStatus = "No Personal Voice yet. Create one in Settings → Accessibility → Personal Voice."
                }
            }
        }
    }
}

private struct VoiceRow: View {
    let voice: AVSpeechSynthesisVoice
    let isSelected: Bool
    let select: () -> Void
    @State private var preview = AVSpeechSynthesizer()

    var body: some View {
        HStack {
            Button(action: select) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading) {
                        Text(voice.name)
                        Text(qualityName).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                preview.stopSpeaking(at: .immediate)
                let u = AVSpeechUtterance(string: "Hi! Let's play!")
                u.voice = voice
                preview.speak(u)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play \(voice.name)")
        }
    }

    private var qualityName: String { VoiceCatalog.qualityName(voice) }
}

/// Shown while only robotic "compact" voices are installed: the one-time steps to get natural ones.
struct NaturalVoicesCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Get a more natural voice", systemImage: "waveform.badge.plus")
                .font(.headline)
            Text("This device only has the basic voices, which can sound robotic. Apple's natural voices are free; download one once and Hum switches to it automatically.")
                .font(.callout)
            #if os(macOS)
            Text("System Settings → Accessibility → Read & Speak (Spoken Content on older Macs) → System voice → Manage Voices… → pick a voice marked Premium or Enhanced, such as Zoe, Ava or Evan.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Open Accessibility settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension") { openURL(url) }
            }
            #else
            Text("Settings → Accessibility → Read & Speak (Spoken Content on older versions) → Voices → English → pick a voice marked Premium or Enhanced, such as Zoe, Ava or Evan, and tap download. Use Wi-Fi: premium voices are large.")
                .font(.callout).foregroundStyle(.secondary)
            #endif
        }
        .padding(.vertical, 4)
    }
}
