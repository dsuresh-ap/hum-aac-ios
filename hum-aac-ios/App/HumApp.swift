// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig
import SwiftData

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
            settings: DeviceSettings(defaults: defaults)))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.container)
                .task { model.launch() }
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

    var body: some View {
        Group {
            switch model.mode {
            case .child: ChildBoardView()
            case .parent: ParentHomeView()
            }
        }
        .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
