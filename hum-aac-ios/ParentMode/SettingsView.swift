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
                    Text("For more natural voices, download an Enhanced or Premium voice in Settings → Accessibility → Spoken Content → Voices, then come back here.")
                }

                Section("How it sounds") {
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
                    Picker("Appearance", selection: $settings.appearance) {
                        Text("Match this device").tag(HumSettings.Appearance.system)
                        Text("Light").tag(HumSettings.Appearance.light)
                        Text("Dark").tag(HumSettings.Appearance.dark)
                    }
                } header: {
                    Text("Tiles")
                } footer: {
                    Text("The sentence strip collects tapped tiles so your child can play them together. It's for later stages of language, so it's off at first. Each tile still speaks on its own.")
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

                Section("For developers") {
                    NavigationLink("Tap-to-sound latency") { DeveloperLatencyView() }
                        .accessibilityIdentifier("developerLatency")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
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

    /// Voices for the device's language, best quality first.
    private func loadVoices() {
        let language = AVSpeechSynthesisVoice.currentLanguageCode().prefix(2)
        voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(String(language)) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
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

    private var qualityName: String {
        if voice.voiceTraits.contains(.isPersonalVoice) { return "Personal Voice" }
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Standard"
        }
    }
}
