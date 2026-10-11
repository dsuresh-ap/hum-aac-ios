// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig
import SwiftData
import UniformTypeIdentifiers

@main
struct HumApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // UI tests start from a clean, in-memory store and fresh settings.
        let testing = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        let defaults = testing ? UserDefaults(suiteName: "HumUITests-\(UUID().uuidString)")! : .standard
        _model = State(initialValue: AppModel(
            container: Persistence.makeContainer(inMemory: testing),
            settings: DeviceSettings(defaults: defaults),
            history: SpeechHistory(fileURL: testing ? nil : SpeechHistory.defaultURL)))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.container)
                .task {
                    model.launch()
                    // Screenshot/UI-test helpers. Only active with -uiTesting (in-memory store).
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-uiTesting") {
                        if args.contains("-skipFirstRun") {
                            model.settings.hasSeenGuidedAccessTip = true
                            model.finishFirstRun(.starter)
                        }
                        if args.contains("-startInParent") { model.mode = .parent }
                        if args.contains("-darkMode") { model.settings.appearance = .dark }
                        if args.contains("-demoFolder") { UITestFixtures.addFoodFolder(model) }
                        if args.contains("-demoHistory") { UITestFixtures.addHistory(model) }
                        if args.contains("-openFolder"), let snack = model.snapshot?.cells.joined().compactMap({ $0 }).first(where: { $0.linkedBoardID != nil }) {
                            model.tap(snack, tapTime: mach_absolute_time())
                        }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 400)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 820)
        .commands {
            // One window: a second copy of the board would only confuse.
            CommandGroup(replacing: .newItem) {}
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.speech.start()
            case .background: model.speech.pause()
            default: break
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showFirstRunImporter = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.needsFirstRun {
                FirstRunView { showFirstRunImporter = true }
            } else {
                switch model.mode {
                case .child: ChildBoardView()
                case .parent: ParentEditorView()
                }
            }
        }
        .preferredColorScheme(colorScheme)
        // "Open in Hum", AirDrop and Finder double-click.
        .onOpenURL { url in if url.isFileURL { model.requestImport(url: url) } }
        // The preview only appears in parent mode. A file that arrives while the child is using
        // Hum waits until a parent opens grown-up settings.
        .sheet(item: Binding(
            get: { model.mode == .parent || showFirstRunImporter ? model.pendingImport : nil },
            set: { if $0 == nil { model.pendingImport = nil } })) { pending in
            ImportPreviewSheet(pending: pending)
        }
        .fileImporter(isPresented: $showFirstRunImporter, allowedContentTypes: [.humPackage, .json, .zip]) { result in
            if case .success(let url) = result { model.requestImport(url: url) }
        }
        .alert("This file couldn't be imported", isPresented: Binding(
            get: { model.mode == .parent && model.importError != nil },
            set: { if !$0 { model.importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.importError ?? "")
        }
        #if os(macOS)
        .dropDestination(for: URL.self) { urls, _ in
            guard model.mode == .parent, let url = urls.first else { return false }
            model.requestImport(url: url)
            return true
        }
        #endif
    }

    private var colorScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Small, deterministic setups for UI tests and screenshots. Only reachable with -uiTesting.
@MainActor
enum UITestFixtures {
    /// Turns the starter "snack" tile into a folder that opens a Food board.
    static func addFoodFolder(_ model: AppModel) {
        guard let home = model.store.boards().first(where: \.isHome),
              let snack = home.placedTiles.first(where: { $0.label == "snack" }) else { return }
        let food = model.store.makeFolder(named: "Food", for: snack, rows: 2, columns: 3)
        let items: [(String, String, String)] = [("crackers", "Let's have crackers!", "🍘"), ("apple", "Let's have apple!", "🍎"),
                                                 ("juice", "Let's have juice!", "🧃"), ("all done", "All done", "✅")]
        for (i, item) in items.enumerated() {
            if let tile = try? model.store.addTile(to: food, row: i / 3, column: i % 3, label: item.0, spokenText: item.1) {
                tile.symbol = item.2
                tile.function = item.0 == "all done" ? .protest : .request
            }
        }
        model.goHome()
    }

    static func addHistory(_ model: AppModel) {
        let start = Date.now.addingTimeInterval(-300)
        for (i, phrase) in ["Hi!", "Let's go!", "Uh oh!", "Uh oh!", "Look at that!", "Let's have crackers!"].enumerated() {
            model.history.add(label: phrase, spokenText: phrase, function: i % 2 == 0 ? .connection : .request, colorHex: nil,
                              at: start.addingTimeInterval(Double(i) * 30))
        }
        model.settings.showHistory = true
    }
}
