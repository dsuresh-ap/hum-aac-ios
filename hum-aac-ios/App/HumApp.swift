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
            container: Persistence.makeContainer(inMemory: testing, iCloud: !testing && DeviceSettings(defaults: defaults).iCloudSyncEnabled),
            settings: DeviceSettings(defaults: defaults),
            history: SpeechHistory(fileURL: testing ? nil : SpeechHistory.defaultURL)))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.container)
                .task {
                    let launchArgs = ProcessInfo.processInfo.arguments
                    if launchArgs.contains("-uiTesting") { model.usesPhoneLayout = launchArgs.contains("-phoneLayout") }
                    model.launch()
                    // Screenshot/UI-test helpers. Only active with -uiTesting (in-memory store).
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-uiTesting") {
                        if args.contains("-skipFirstRun") {
                            model.settings.hasSeenGuidedAccessTip = true
                            model.finishFirstRun(.starter)
                        }
                        if args.contains("-demoPendingImport") { UITestFixtures.queueImport(model) }
                        if args.contains("-startInParent") { model.mode = .parent }
                        if args.contains("-darkMode") { model.settings.appearance = .dark }
                        if args.contains("-demoFolder") { UITestFixtures.addFoodFolder(model) }
                        if args.contains("-wideHome") { UITestFixtures.widenHome(model) }
                        if args.contains("-tallHome") { UITestFixtures.lengthenHome(model) }
                        if args.contains("-demoHistory") { UITestFixtures.addHistory(model) }
                        // A .hum file to import, as if it arrived through "Open in Hum".
                        if let i = args.firstIndex(of: "-importFile"), i + 1 < args.count {
                            model.requestImport(url: URL(fileURLWithPath: args[i + 1]))
                        }
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
        #endif
        .commands { EditorMenuCommands() }
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
        // The preview only appears in parent mode (or during setup, where a parent is choosing "Import a
        // setup"). A file that arrives while the child is using Hum waits until a parent opens grown-up
        // settings. Setup & sharing shows its own.
        .modifier(ImportPreviewHost(isActive: (model.mode == .parent || model.needsFirstRun) && !model.importHostedBySheet))
        .fileImporter(isPresented: $showFirstRunImporter, allowedContentTypes: [.humPackage, .json, .zip]) { result in
            if case .success(let url) = result { model.requestImport(url: url) }
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
    /// Makes Home 6 columns wide (tiles keep their spots), too wide for a phone: it gets a phone layout.
    static func widenHome(_ model: AppModel) {
        guard let home = model.store.boards().first(where: \.isHome) else { return }
        try? model.store.resize(home, rows: home.rows, columns: 6)
        model.goHome()
    }

    /// Makes Home 12 rows tall (tiles keep their spots) with a tile in the last row: the board scrolls.
    static func lengthenHome(_ model: AppModel) {
        guard let home = model.store.boards().first(where: \.isHome) else { return }
        try? model.store.resize(home, rows: 12, columns: home.columns)
        if let tile = try? model.store.addTile(to: home, row: 11, column: 0, label: "bottom", spokenText: "All the way down!") {
            tile.symbol = "⬇️"
        }
        model.goHome()
    }

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

    /// An import of one new tile ("All aboard!") into Home's free spot, waiting for the preview.
    static func queueImport(_ model: AppModel) {
        var doc = ConfigBridge.export(boards: model.store.boards()).document
        guard let home = doc.boards.firstIndex(where: \.isHome) else { return }
        doc.boards[home].tiles = [HumTile(label: "all aboard", spokenText: "All aboard!", row: 3, column: 3, function: .request)]
        model.pendingImport = ImportService(model: model).prepare(loaded: LoadedConfig(document: doc), fileName: "Trains.hum")
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
