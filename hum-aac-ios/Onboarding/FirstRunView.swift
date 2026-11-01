// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AVFoundation
import HumConfig

/// First-run setup, a few minutes at most:
/// Welcome → How Hum works → Voice → Tile size → Extras → Start.
struct FirstRunView: View {
    @Environment(AppModel.self) private var model
    let onImport: () -> Void

    enum Step: Int, CaseIterable { case welcome, howItWorks, voice, grid, extras, start }
    static let gridOptions: [(Int, Int)] = [(2, 2), (3, 3), (3, 4), (4, 5)]
    @State private var step: Step = .welcome
    @State private var rows = 3
    @State private var columns = 3
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var preview = AVSpeechSynthesizer()
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPad and Mac have room for bigger pictures on the welcome and grid steps.
    private var roomy: Bool { sizeClass == .regular }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                .padding(.horizontal, 24).padding(.top, 16)
                .accessibilityHidden(true)
            Group {
                switch step {
                case .welcome: welcome
                case .howItWorks: howItWorks
                case .voice: voicePicker
                case .grid: gridPicker
                case .extras: extras
                case .start: startChoice
                }
            }
            .frame(maxWidth: roomy ? 760 : 640, maxHeight: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear(perform: setDefaults)
        .task { voices = await VoiceCatalog.load() }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            // The product in one picture: whole phrases on soft keys, "no" as big as "let's go".
            // The biggest keys that fit: three 140 pt keys are wider than an iPhone (BUGS.md, HUM-009).
            ViewThatFits(in: .horizontal) {
                ForEach([200, 140, 100] as [CGFloat], id: \.self) { size in
                    HStack(spacing: 14) {
                        SampleKey(symbol: "🚀", label: String(localized: "Let's go!"), function: .request, size: size)
                        SampleKey(symbol: "🙅", label: String(localized: "No thank you"), function: .protest, size: size)
                        SampleKey(symbol: "👀", label: String(localized: "Look at that!"), function: .comment, size: size)
                    }
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("Welcome to Hum")
                    .font(.system(size: roomy ? 60 : 44, weight: .semibold, design: .serif))
                    .minimumScaleFactor(0.7)
                Text("A voice for your child in whole phrases, the way they learn language.")
                    .font(roomy ? .title2 : .title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .frame(maxWidth: roomy ? 560 : 440)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            primaryButton("Let's set up") { step = .howItWorks }
                .accessibilityIdentifier("firstRun.start")
        }
    }

    // MARK: How Hum works

    private var howItWorks: some View {
        stepPage(back: .welcome, next: .voice) {
            stepTitle("How Hum works")
            Text("Try it: tap a tile.").foregroundStyle(.secondary)
            // Real keys the parent can press: they sink and speak, like on the child's board.
            HStack(spacing: 14) {
                TryKey(symbol: "🍎", label: String(localized: "I want a snack"), function: .request, size: roomy ? 150 : 112) {
                    say(String(localized: "I want a snack, please!", comment: "Spoken when a parent tries a tile during setup."))
                }
                TryKey(symbol: "✋", label: String(localized: "All done"), function: .protest, size: roomy ? 150 : 112) {
                    say(String(localized: "All done!", comment: "Spoken when a parent tries a tile during setup."))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityIdentifier("firstRun.tryTiles")

            VStack(alignment: .leading, spacing: 18) {
                HowRow(glyph: "speaker.wave.2.fill",
                       title: "One tap, one whole phrase",
                       detail: "Hum speaks as soon as a finger touches a tile. Tapping the same tile again and again is fine, because repeating is talking too.")
                HowRow(glyph: "folder.fill",
                       title: "Folders hold more tiles",
                       detail: "A tile with a folder corner opens its own page, like “Food” or “Outside”. Home and Back at the top bring your child out again.")
                HowRow(glyph: "lock.fill",
                       title: "Grown-up settings are behind the lock",
                       detail: "Press and hold the lock in the top corner for 3 seconds. That's where you add tiles, swap in real photos and record voices.")
            }
            .padding(.top, 4)
        }
    }

    // MARK: Voice

    private var voicePicker: some View {
        stepPage(back: .howItWorks, next: .grid, skip: {
            model.settings.voiceIdentifier = nil
            step = .grid
        }) {
            stepTitle("Pick a voice")
            Text("Tap ▶ to listen. You can change this any time.").foregroundStyle(.secondary)
            if VoiceCatalog.onlyCompact(voices) {
                NaturalVoicesCard()
                    .fixedSize(horizontal: false, vertical: true)  // all the steps, never "…"
                    .padding(14)
                    .background(Theme.editBand, in: .rect(cornerRadius: 14))
            }
            VStack(spacing: 10) {
                ForEach(voices.prefix(4), id: \.identifier) { voice in
                    voiceRow(voice)
                }
            }
            styleChoice
            if !voices.isEmpty && !VoiceCatalog.onlyCompact(voices) {
                DisclosureGroup("Where to get more voices") {
                    MoreVoicesSteps()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .font(.callout)
                .tint(Theme.ink)
            }
        }
    }

    private func voiceRow(_ voice: AVSpeechSynthesisVoice) -> some View {
        // With no choice yet, the voice Hum would use is the one marked.
        let selected = (model.settings.voiceIdentifier ?? model.defaultVoiceIdentifier) == voice.identifier
        return HStack {
            Button {
                model.settings.voiceIdentifier = voice.identifier
                model.applySpeechSettings()
                play(voice)
            } label: {
                HStack {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name).font(.title3)
                        Text(VoiceCatalog.qualityName(voice)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voice.name)
            .accessibilityValue(VoiceCatalog.qualityName(voice))
            Button { play(voice) } label: { Image(systemName: "play.circle.fill").font(.title) }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(voice.name)")
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .padding(14)
        .background(Theme.chrome, in: .rect(cornerRadius: 14))
    }

    /// Natural, Younger or Calm: the same quick styles as in Settings.
    private var styleChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it sounds").font(.headline)
            Picker("How it sounds", selection: Binding(
                get: { VoiceStyle.matching(rate: model.settings.rate, pitch: model.settings.pitch) },
                set: { style in
                    guard let v = style.values else { return }
                    model.settings.rate = v.rate
                    model.settings.pitch = v.pitch
                    model.applySpeechSettings()
                    say(SpeechSamples.tryVoice)
                })) {
                ForEach(VoiceStyle.allCases.filter { $0 != .custom }, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("“Younger” makes any voice a little higher and slower. Apple doesn't have children's voices. For a real child's voice, an older sibling or cousin can record tiles later.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    // MARK: Tile size

    private var gridPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            // The roomy layout when it fits; at the largest text sizes it scrolls, so Next stays on screen.
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    gridChoices(spaced: roomy)
                    Spacer()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { gridChoices(spaced: false) }
                }
            }
            footer(back: .voice, next: .extras)
        }
    }

    @ViewBuilder private func gridChoices(spaced: Bool) -> some View {
        stepTitle("How many tiles on a screen?")
        Text("Fewer, bigger tiles are easier to start with. Rows × columns.").foregroundStyle(.secondary)
        if spaced { Spacer() }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: roomy ? 160 : 130), spacing: roomy ? 20 : 12)], spacing: roomy ? 20 : 12) {
            ForEach(Self.gridOptions.indices, id: \.self) { index in
                let option = Self.gridOptions[index]
                let selected = rows == option.0 && columns == option.1
                Button {
                    rows = option.0
                    columns = option.1
                } label: {
                    VStack(spacing: 10) {
                        GridPreview(rows: option.0, columns: option.1).frame(width: roomy ? 140 : 90, height: roomy ? 140 : 90)
                        Text("\(option.0) × \(option.1)").font(roomy ? .title3.weight(.semibold) : .headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Theme.chrome, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: Extras

    private var extras: some View {
        @Bindable var settings = model.settings
        return stepPage(back: .grid, next: .start) {
            stepTitle("Extras for your child's screen")
            Text("Most are off, so the screen stays calm. You can change any of them later in Settings.")
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                ExtraToggle(isOn: Binding(get: { settings.activation == .touchDown },
                                          set: { settings.activation = $0 ? .touchDown : .touchUp }),
                            glyph: "hand.point.up.left.fill",
                            title: "Speak as soon as a finger touches",
                            detail: "This is the fastest. Turn it off if your child often brushes tiles by accident. A tile then speaks when the finger lifts.")
                    .accessibilityIdentifier("firstRun.touchDown")
                ExtraToggle(isOn: $settings.showHistory, glyph: "clock.arrow.circlepath",
                            title: "History box",
                            detail: "A small row above the tiles shows what was said last, so you can catch up if you missed it.")
                    .accessibilityIdentifier("firstRun.history")
                ExtraToggle(isOn: $settings.showWordFinder, glyph: "magnifyingglass",
                            title: "Word finder",
                            detail: "Adds a magnifier at the top. Look up a word, and Hum lights up the way to its tile without saying it.")
                ExtraToggle(isOn: $settings.sentenceStrip, glyph: "text.line.first.and.arrowtriangle.forward",
                            title: "Sentence strip",
                            detail: "Tapped tiles collect in a strip that plays them together. Turn it on once your child starts mixing phrases into new ones.")
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .phone {
                    ExtraToggle(isOn: $settings.haptics, glyph: "iphone.radiowaves.left.and.right",
                                title: "Light vibration on tap",
                                detail: "Some children like feeling the tap. Some don't.")
                }
                #endif
            }
            #if os(iOS)
            guidedAccessCard
            #endif
        }
    }

    #if os(iOS)
    /// Guided Access keeps the child inside Hum. Explained here, so the editor doesn't repeat it later.
    private var guidedAccessCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Keep your child in Hum", systemImage: "lock.iphone").font(.headline)
            Text("Turn on Guided Access in Settings → Accessibility → Guided Access. Then, with Hum open, triple-click the side (or Home) button to start it.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.editBand, in: .rect(cornerRadius: 14))
        .padding(.top, 6)
        .onAppear { model.settings.hasSeenGuidedAccessTip = true }
    }
    #endif

    // MARK: Start

    private var startChoice: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Scrolls at the largest text sizes, so the footnote never hides the start buttons.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    startChoices
                    startFootnote
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack {
                Button("Back") { step = .extras }
                Spacer()
            }
        }
    }

    @ViewBuilder private var startChoices: some View {
        stepTitle("How do you want to start?")
        choice("Starter board", starterDetail, "sparkles") {
            useChosenSizeForNewFolders()
            keepingExtras { model.finishFirstRun(.starter) }
            growHomeToChosenSize()
        }
        .accessibilityIdentifier("firstRun.starter")
        choice("Empty board", String(localized: "A blank \(rows) × \(columns) board to fill with your child's own phrases."), "square.dashed") {
            useChosenSizeForNewFolders()
            model.finishFirstRun(.empty(rows: rows, columns: columns))
        }
        .accessibilityIdentifier("firstRun.empty")
        // Setup finishes only once the import does: cancelling comes back here, and the file's own
        // Home becomes Home because nothing was made before it (BUGS.md, HUM-004).
        choice("Import boards", String(localized: "A Hum file from another device, or boards someone made for your child."), "square.and.arrow.down") {
            useChosenSizeForNewFolders()
            onImport()
        }
        .accessibilityIdentifier("firstRun.import")
    }

    /// How to get back into settings, and what Hum is. A footnote, not a page.
    private var startFootnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                Text("To change things later, press and hold the lock for 3 seconds.")
                Text("Hum is a communication tool, not therapy or a medical device.")
            }
            .foregroundStyle(.secondary)
            Link("Privacy policy", destination: HumLinks.privacy)
                .accessibilityHint("Opens in your web browser")
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 8)
    }

    /// The starter board has its own 5 × 4 size. A smaller choice is used for new folders instead,
    /// and the card says so, rather than squeezing the starter's tiles away (BUGS.md, HUM-003).
    private var starterDetail: String {
        guard rows < 5 || columns < 4, rows * columns < 20 else {
            return String(localized: "18 whole phrases like “Let's go!”, “All done” and “Too loud”. Replace the pictures with real photos later.")
        }
        return String(localized: "A 5 × 4 board with 18 whole phrases, like “Let's go!”, “All done” and “Too loud”. Replace the pictures with real photos later. New folders use the size you picked: \(rows) × \(columns).")
    }

    private func useChosenSizeForNewFolders() {
        model.settings.newBoardRows = rows
        model.settings.newBoardColumns = columns
    }

    /// The starter file carries its own speech settings. The parent's choices on the Extras step win.
    private func keepingExtras(_ body: () -> Void) {
        let (activation, strip) = (model.settings.activation, model.settings.sentenceStrip)
        body()
        model.settings.activation = activation
        model.settings.sentenceStrip = strip
    }

    // MARK: Helpers

    private func stepTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(.largeTitle, design: .serif, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// A step's content, which scrolls at the largest text sizes, above its Back / Skip / Next buttons.
    private func stepPage<Content: View>(back: Step, next: Step, skip: (() -> Void)? = nil,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            footer(back: back, next: next, skip: skip)
        }
    }

    private func footer(back: Step, next: Step, skip: (() -> Void)? = nil) -> some View {
        HStack(spacing: 20) {
            Button("Back") { step = back }
            Spacer()
            if let skip { Button("Skip", action: skip) }
            primaryButton("Next") { step = next }
        }
    }

    private func choice(_ title: LocalizedStringKey, _ detail: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title).frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Theme.chrome, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.title3.weight(.semibold)).frame(minWidth: 160).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func play(_ voice: AVSpeechSynthesisVoice) {
        speak(SpeechSamples.tryVoice, voice: voice)
    }

    /// Says `text` with the chosen voice (or the one Hum would pick) and the chosen style.
    /// Looks the voice up off the main actor, like the board does (HUM-056).
    private func say(_ text: String) {
        let id = model.settings.voiceIdentifier ?? model.defaultVoiceIdentifier ?? ""
        Task { speak(text, voice: await SpeechRenderer.voice(id)) }
    }

    private func speak(_ text: String, voice: AVSpeechSynthesisVoice?) {
        preview.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = Float(model.settings.rate)
        u.pitchMultiplier = Float(model.settings.pitch)
        u.volume = Float(model.settings.volume)
        preview.speak(u)
    }

    private func setDefaults() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad { (rows, columns) = (4, 5) }
        #else
        (rows, columns) = (4, 5)
        #endif
    }

    /// The starter board is 5 × 4. If the parent picked a bigger grid, grow Home (growing never moves tiles),
    /// which leaves empty spots for the child's own phrases.
    private func growHomeToChosenSize() {
        guard let home = model.store.boards().first(where: \.isHome) else { return }
        let newRows = max(home.rows, rows), newColumns = max(home.columns, columns)
        if newRows != home.rows || newColumns != home.columns {
            try? model.store.resize(home, rows: newRows, columns: newColumns)
            model.rebuildSnapshot()
        }
    }
}

/// One thing to know about Hum, beside the mark the parent will see on the child's screen.
private struct HowRow: View {
    let glyph: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: glyph)
                .font(.title3)
                .foregroundStyle(Theme.ink.opacity(0.7))
                .frame(width: 52, height: 52)
                .background(Theme.chrome, in: .rect(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A setting on the Extras step: what it adds to the child's screen, and a switch.
private struct ExtraToggle: View {
    @Binding var isOn: Bool
    let glyph: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: glyph)
                    .font(.title3)
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(.accentColor)
        .padding(14)
        .background(Theme.chrome, in: .rect(cornerRadius: 14))
    }
}

/// Where the free natural voices are, for devices that already have one.
private struct MoreVoicesSteps: View {
    var body: some View {
        #if os(macOS)
        Text("System Settings → Accessibility → Read & Speak → System voice → Manage Voices. Voices marked Premium or Enhanced sound most natural. Hum lists new ones here right away.")
            .foregroundStyle(.secondary)
        #else
        Text("Settings → Accessibility → Read & Speak → Voices → your language. Voices marked Premium or Enhanced sound most natural. They're large, so use Wi-Fi. Hum lists new ones here right away.")
            .foregroundStyle(.secondary)
        #endif
    }
}

/// A small, static tile for the welcome screen.
private struct SampleKey: View {
    let symbol: String
    let label: String
    let function: TileFunction
    var size: CGFloat = 140

    var body: some View {
        KeyFace(symbol: symbol, label: label, function: function, size: size, pressed: false)
    }
}

/// A tile the parent can press during setup: it sinks onto its edge and speaks, like the real thing.
private struct TryKey: View {
    let symbol: String
    let label: String
    let function: TileFunction
    var size: CGFloat = 120
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KeyFace(symbol: symbol, label: label, function: function, size: size, pressed: false)
        }
        .buttonStyle(KeyPressStyle(symbol: symbol, label: label, function: function, size: size))
        .accessibilityLabel(label)
        .accessibilityHint("Says the phrase")
    }
}

private struct KeyPressStyle: ButtonStyle {
    let symbol: String
    let label: String
    let function: TileFunction
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        KeyFace(symbol: symbol, label: label, function: function, size: size, pressed: configuration.isPressed)
            .animation(Theme.pressAnimation, value: configuration.isPressed)
    }
}

/// A soft key: a face over a darker edge. Pressed, the face sinks onto the edge.
private struct KeyFace: View {
    let symbol: String
    let label: String
    let function: TileFunction
    let size: CGFloat
    let pressed: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(symbol).font(.system(size: size * 0.32))
            Text(label).font(.system(size: max(13, size * 0.12), weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center).minimumScaleFactor(0.7).padding(.horizontal, 6)
        }
        .frame(width: size, height: size)
        .background(Theme.tileColor(function: function, hex: nil), in: .rect(cornerRadius: Theme.tileCorner, style: .continuous))
        .offset(y: pressed ? Theme.keyDepth : 0)
        .background(alignment: .bottom) {
            RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                .fill(Theme.tileEdge(function: function, hex: nil))
                .offset(y: Theme.keyDepth)
        }
        .padding(.bottom, Theme.keyDepth)
    }
}
