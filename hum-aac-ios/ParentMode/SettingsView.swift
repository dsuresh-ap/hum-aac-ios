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
    /// The voice list starts short (the best few, plus the one in use), so the other settings are close.
    @State private var showAllVoices = false
    /// The parent turned on "What's this?" but Hum may not use the camera.
    @State private var cameraDenied = false

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
                                model.speech.speak(SpeechSamples.tryVoice)
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
                    Text("“Younger” makes any voice higher and a little slower. Apple doesn't include children's voices; for a real child's voice, ask an older sibling or cousin to record tiles (edit a tile → Record your voice).")
                }

                Section {
                    ForEach(shownVoices, id: \.identifier) { voice in
                        VoiceRow(voice: voice, isSelected: voice.identifier == currentVoiceID) {
                            settings.voiceIdentifier = voice.identifier
                            voiceChanged()
                        }
                    }
                    if voices.count > shownVoices.count {
                        Button("Show all \(voices.count) voices") { showAllVoices = true }
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
                    Button("Play a sample", systemImage: "play.circle") { model.speech.speak(SpeechSamples.tryVoice) }
                }

                Section {
                    Picker("If a tile is tapped while Hum is talking", selection: $settings.retrigger) {
                        Text("Stop and say the new tile").tag(HumSettings.Retrigger.restart)
                        Text("Finish first").tag(HumSettings.Retrigger.finish)
                        Text("Say both").tag(HumSettings.Retrigger.overlap)
                    }
                    .onChange(of: settings.retrigger) { model.applySpeechSettings() }
                    Picker("Speak when", selection: $settings.activation) {
                        Text("As soon as a finger touches (fastest)").tag(HumSettings.Activation.touchDown)
                        Text("When the finger lifts off").tag(HumSettings.Activation.touchUp)
                    }
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        Toggle("Light vibration on tap", isOn: $settings.haptics)
                    }
                    #endif
                } header: {
                    Text("Tapping")
                } footer: {
                    Text("Every tap always makes a sound, even very fast repeated taps. Repeated tapping is communication too. On a board that scrolls, tiles speak when the finger lifts, so scrolling never speaks.")
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
                    Toggle("Word finder (magnifier at the top)", isOn: $settings.showWordFinder)
                        .accessibilityIdentifier("wordFinderToggle")
                    Picker("Appearance", selection: $settings.appearance) {
                        Text("Match this device").tag(HumSettings.Appearance.system)
                        Text("Light").tag(HumSettings.Appearance.light)
                        Text("Dark").tag(HumSettings.Appearance.dark)
                    }
                } header: {
                    Text("Tiles")
                } footer: {
                    Text("The sentence strip collects tapped tiles so your child can play them together; it's for when your child starts mixing words into new sentences. The history box shows what was said recently, so you can catch up if you missed it. The word finder looks up a word and lights up the way to its tile, without saying it, so the path is learned. All three are off at first, and each tile always speaks on its own.")
                }

                whatsThisSection

                Section {
                    Toggle("Go back to Home after a tile in a folder speaks", isOn: $settings.returnHomeAfterFolderTap)
                    LabeledContent("Tile size for new folders") {
                        HStack(spacing: 8) {
                            Text("\(settings.newBoardColumns) across").monospacedDigit()
                        }
                    }
                    GridSizePicker(columns: $settings.newBoardColumns)
                } header: {
                    Text("Folders and boards")
                } footer: {
                    Text("To change the tile size on a board you already have, open it in edit mode and tap the size button at the top right.")
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
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Hum", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("settings.about")
                } footer: {
                    Text("Version, privacy policy, help, symbol credits and license.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(macOS)
            .navigationSubtitle("Changes save as you make them")
            #else
            .safeAreaInset(edge: .bottom) {
                Text("Changes save as you make them.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(.bar)
            }
            #endif
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

    /// The best 5 voices and the one in use, or all of them.
    /// "What's this?" camera for the child. Turning it on asks for the camera now, in grown-up settings,
    /// so the child never sees a permission prompt.
    private var whatsThisSection: some View {
        let availability = model.whatsThisAvailability
        return Section {
            Toggle("“What's this?” camera", isOn: Binding(
                get: { model.settings.whatsThisCamera && availability == .available },
                set: { turnOnWhatsThis($0) }))
                .disabled(availability != .available)
                .accessibilityIdentifier("whatsThisToggle")
            switch availability {
            case .notInEnglish:
                Text("Only in English for now. The words come from Apple's picture recognition on this device, which knows English words.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .noCamera:
                Text("This device has no camera.").font(.footnote).foregroundStyle(.secondary)
            case .available:
                if cameraDenied {
                    #if os(macOS)
                    Text("Hum isn't allowed to use the camera. You can allow it in System Settings → Privacy & Security → Camera.")
                        .font(.footnote).foregroundStyle(.orange)
                    #else
                    Text("Hum isn't allowed to use the camera. You can allow it in Settings → Privacy & Security → Camera.")
                        .font(.footnote).foregroundStyle(.orange)
                    #endif
                }
            }
        } header: {
            Text("What's this?")
        } footer: {
            Text("Adds a camera button at the top of your child's board. Your child points it at something, and Hum shows up to three words for it. A word speaks only when your child taps it. The guesses are made on this device and can be wrong. Pictures aren't kept.")
        }
    }

    private func turnOnWhatsThis(_ on: Bool) {
        guard on else {
            model.settings.whatsThisCamera = false
            return
        }
        Task {
            let allowed = model.usesFakeCamera ? true : await WhatsThisCamera.requestCamera()
            cameraDenied = !allowed
            model.settings.whatsThisCamera = allowed
        }
    }

    private var shownVoices: [AVSpeechSynthesisVoice] {
        if showAllVoices { return voices }
        let top = Array(voices.prefix(5))
        guard !top.contains(where: { $0.identifier == currentVoiceID }),
              let current = voices.first(where: { $0.identifier == currentVoiceID }) else { return top }
        return top + [current]
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
                    personalVoiceStatus = String(localized: "Personal Voice is allowed. Your voice is now in the list.")
                    loadVoices()
                    if let mine = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.voiceTraits.contains(.isPersonalVoice) }) {
                        model.settings.voiceIdentifier = mine.identifier
                        voiceChanged()
                    }
                case .denied:
                    personalVoiceStatus = String(localized: "Personal Voice was not allowed. You can change this in Settings → Accessibility → Personal Voice.")
                case .unsupported:
                    personalVoiceStatus = String(localized: "This device doesn't support Personal Voice.")
                default:
                    personalVoiceStatus = String(localized: "No Personal Voice yet. Create one in Settings → Accessibility → Personal Voice.")
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
                let u = AVSpeechUtterance(string: SpeechSamples.voicePreview)
                u.voice = voice
                preview.speak(u)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play \(voice.name)")
            .help("Hear \(voice.name)")
        }
    }

    private var qualityName: String { VoiceCatalog.qualityName(voice) }
}

/// What Hum says to show off a voice. Spoken in the device's language, so they're translated too.
enum SpeechSamples {
    static var tryVoice: String { String(localized: "Let's go to the park!", comment: "Spoken to try out a voice or the voice settings.") }
    static var voicePreview: String { String(localized: "Hi! Let's play!", comment: "Spoken when a parent previews one voice in the list.") }
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
            Text("Settings → Accessibility → Read & Speak (Spoken Content on older versions) → Voices → your language → pick a voice marked Premium or Enhanced, such as Zoe, Ava or Evan, and tap download. Use Wi-Fi: premium voices are large.")
                .font(.callout).foregroundStyle(.secondary)
            #endif
        }
        .padding(.vertical, 4)
    }
}
