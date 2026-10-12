// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData
@testable import Hum

/// Models made by tests, kept alive until the test run ends. Freeing a store while its undo manager still
/// has an open run-loop undo group crashes SwiftData at the next run-loop turn (in whatever test runs then).
@MainActor private var liveModels: [AppModel] = []

/// A fresh app model with an in-memory store, its own settings and no saved history.
@MainActor
func makeModel(starter: Bool = true) -> AppModel {
    let defaults = UserDefaults(suiteName: "HumTests-\(UUID().uuidString)")!
    let model = AppModel(container: Persistence.makeContainer(inMemory: true),
                         settings: DeviceSettings(defaults: defaults),
                         history: SpeechHistory(fileURL: nil))
    // Tests run on an iPhone simulator; the phone layout has its own tests (PhoneLayoutTests).
    model.usesPhoneLayout = false
    if starter { model.finishFirstRun(.starter) }
    liveModels.append(model)
    return model
}

@MainActor
extension AppModel {
    /// Ends the current "event", like a tap does in the app. Tests don't turn the run loop by themselves,
    /// so without this the undo manager's per-event group would hold every change the test made, and one
    /// Undo would undo all of them.
    func endEvent() {
        RunLoop.current.run(until: .now)
    }

    /// Never force-unwrap in tests: a crash takes down the whole test host app.
    var home: Board { store.boards().first(where: \.isHome) ?? Board(name: "MISSING HOME", rows: 1, columns: 2) }

    /// "row,column" → label for every placed tile on a board.
    func layout(_ board: Board) -> [String: String] {
        Dictionary(uniqueKeysWithValues: board.placedTiles.map { ("\($0.row!),\($0.column!)", $0.label) })
    }
}
