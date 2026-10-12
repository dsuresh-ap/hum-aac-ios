// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AVFoundation
import HumConfig

/// First-run setup, under two minutes: Welcome → Voice → Grid size → Start.
struct FirstRunView: View {
    @Environment(AppModel.self) private var model
    let onImport: () -> Void

    enum Step: Int, CaseIterable { case welcome, voice, grid, start }
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
                case .voice: voicePicker
                case .grid: gridPicker
                case .start: startChoice
                }
            }
            .frame(maxWidth: roomy ? 760 : 640, maxHeight: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear(perform: setDefaults)
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            // The product in one picture: whole phrases on soft keys, "no" as big as "let's go".
            // The biggest keys that fit: three 140 pt keys are wider than an iPhone (BUGS.md, HUM-009).
            ViewThatFits(in: .horizontal) {
                ForEach([200, 140, 100] as [CGFloat], id: \.self) { size in
                    HStack(spacing: 14) {
                        SampleKey(symbol: "🚀", label: "Let's go!", function: .request, size: size)
                        SampleKey(symbol: "🙅", label: "No thank you", function: .protest, size: size)
                        SampleKey(symbol: "👀", label: "Look at that!", function: .comment, size: size)
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
            primaryButton("Let's set up") { step = .voice }
                .accessibilityIdentifier("firstRun.start")
        }
    }

    private var voicePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick a voice").font(.system(.largeTitle, design: .serif, weight: .semibold))
            Text("Tap ▶ to listen. You can change this any time.").foregroundStyle(.secondary)
            if VoiceCatalog.onlyCompactVoicesInstalled {
                NaturalVoicesCard()
                    .fixedSize(horizontal: false, vertical: true)  // all the steps, never "…"
                    .padding(14)
                    .background(Theme.editBand, in: .rect(cornerRadius: 14))
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(voices.prefix(4), id: \.identifier) { voice in
                        // With no choice yet, the voice Hum would use is the one marked.
                        let selected = (model.settings.voiceIdentifier ?? SpeechService.defaultVoiceIdentifier()) == voice.identifier
                        HStack {
                            Button {
                                model.settings.voiceIdentifier = voice.identifier
                                play(voice)
                            } label: {
                                HStack {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    Text(voice.name).font(.title3)
                                    Spacer()
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            Button { play(voice) } label: { Image(systemName: "play.circle.fill").font(.title) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Play \(voice.name)")
                        }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .padding(14)
                        .background(Theme.chrome, in: .rect(cornerRadius: 14))
                    }
                }
            }
            HStack {
                Button("Skip") {
                    model.settings.voiceIdentifier = nil
                    step = .grid
                }
                Spacer()
                primaryButton("Next") { step = .grid }
            }
        }
    }

    private var gridPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How many tiles on a screen?").font(.system(.largeTitle, design: .serif, weight: .semibold))
            Text("Fewer, bigger tiles are easier to start with. Rows × columns.").foregroundStyle(.secondary)
            if roomy { Spacer() }
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
            Spacer()
            HStack {
                Button("Back") { step = .voice }
                Spacer()
                primaryButton("Next") { step = .start }
            }
        }
    }

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
            Button("Back") { step = .grid }
        }
    }

    @ViewBuilder private var startChoices: some View {
        Text("How do you want to start?").font(.system(.largeTitle, design: .serif, weight: .semibold))
        choice("Starter board", starterDetail, "sparkles") {
            useChosenSizeForNewFolders()
            model.finishFirstRun(.starter)
            growHomeToChosenSize()
        }
        .accessibilityIdentifier("firstRun.starter")
        choice("Empty board", "A blank \(rows) × \(columns) board to fill with your child's own phrases.", "square.dashed") {
            useChosenSizeForNewFolders()
            model.finishFirstRun(.empty(rows: rows, columns: columns))
        }
        .accessibilityIdentifier("firstRun.empty")
        // Setup finishes only once the import does: cancelling comes back here, and the file's own
        // Home becomes Home because nothing was made before it (BUGS.md, HUM-004).
        choice("Import a setup", "A Hum file from another device, or one made with a coding agent.", "square.and.arrow.down") {
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
        let phrases = "18 whole phrases like \"Let's go!\", \"All done\" and \"Too loud\". Replace the pictures with real photos later."
        guard rows < 5 || columns < 4, rows * columns < 20 else { return phrases }
        return "A 5 × 4 board with " + phrases.prefix(1).lowercased() + phrases.dropFirst()
            + " New folders use your \(rows) × \(columns) size."
    }

    private func useChosenSizeForNewFolders() {
        model.settings.newBoardRows = rows
        model.settings.newBoardColumns = columns
    }

    // MARK: Helpers

    private func choice(_ title: String, _ detail: String, _ icon: String, action: @escaping () -> Void) -> some View {
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

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.title3.weight(.semibold)).frame(minWidth: 160).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func play(_ voice: AVSpeechSynthesisVoice) {
        preview.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: "Let's go to the park!")
        u.voice = voice
        preview.speak(u)
    }

    private func setDefaults() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad { (rows, columns) = (4, 5) }
        #else
        (rows, columns) = (4, 5)
        #endif
        voices = VoiceCatalog.voices()
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

/// A small, static tile for the welcome screen.
private struct SampleKey: View {
    let symbol: String
    let label: String
    let function: TileFunction
    var size: CGFloat = 140

    var body: some View {
        VStack(spacing: 8) {
            Text(symbol).font(.system(size: size * 0.32))
            Text(label).font(.system(size: max(13, size * 0.12), weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center).minimumScaleFactor(0.7).padding(.horizontal, 6)
        }
        .frame(width: size, height: size)
        .background(Theme.tileColor(function: function, hex: nil), in: .rect(cornerRadius: Theme.tileCorner, style: .continuous))
        .background(alignment: .bottom) {
            RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                .fill(Theme.tileEdge(function: function, hex: nil))
                .offset(y: Theme.keyDepth)
        }
    }
}
