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
            .frame(maxWidth: 640, maxHeight: .infinity)
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
            HStack(spacing: 14) {
                SampleKey(symbol: "🚀", label: "Let's go!", function: .request)
                SampleKey(symbol: "🙅", label: "No thank you", function: .protest)
                SampleKey(symbol: "👀", label: "Look at that!", function: .comment)
            }
            .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("Welcome to Hum")
                    .font(.system(size: 44, weight: .semibold, design: .serif))
                Text("A voice for your child in whole phrases, the way they learn language.")
                    .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
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
                    .padding(14)
                    .background(Theme.editBand, in: .rect(cornerRadius: 14))
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(voices.prefix(4), id: \.identifier) { voice in
                        let selected = model.settings.voiceIdentifier == voice.identifier
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                ForEach(Self.gridOptions.indices, id: \.self) { index in
                    let option = Self.gridOptions[index]
                    let selected = rows == option.0 && columns == option.1
                    Button {
                        rows = option.0
                        columns = option.1
                    } label: {
                        VStack(spacing: 10) {
                            GridPreview(rows: option.0, columns: option.1).frame(width: 90, height: 90)
                            Text("\(option.0) × \(option.1)").font(.headline)
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
            Text("How do you want to start?").font(.system(.largeTitle, design: .serif, weight: .semibold))
            choice("Starter board", "18 whole phrases like \"Let's go!\", \"All done\" and \"Too loud\". Replace the pictures with real photos later.", "sparkles") {
                model.finishFirstRun(.starter)
                growHomeToChosenSize()
            }
            .accessibilityIdentifier("firstRun.starter")
            choice("Empty board", "A blank \(rows) × \(columns) board to fill with your child's own phrases.", "square.dashed") {
                model.finishFirstRun(.empty(rows: rows, columns: columns))
            }
            .accessibilityIdentifier("firstRun.empty")
            choice("Import a setup", "A .hum file from another device, or one made with a coding agent.", "square.and.arrow.down") {
                model.finishFirstRun(.empty(rows: rows, columns: columns))
                onImport()
            }
            Spacer()
            Button("Back") { step = .grid }
        }
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

    var body: some View {
        VStack(spacing: 8) {
            Text(symbol).font(.system(size: 44))
            Text(label).font(.system(.headline, design: .rounded)).foregroundStyle(Theme.ink)
        }
        .frame(width: 140, height: 140)
        .background(Theme.tileColor(function: function, hex: nil), in: .rect(cornerRadius: Theme.tileCorner, style: .continuous))
        .background(alignment: .bottom) {
            RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                .fill(Theme.tileEdge(function: function, hex: nil))
                .offset(y: Theme.keyDepth)
        }
    }
}
