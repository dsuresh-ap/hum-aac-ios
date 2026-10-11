// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData
@testable import Hum

/// A fresh app model with an in-memory store, its own settings and no saved history.
@MainActor
func makeModel(starter: Bool = true) -> AppModel {
    let defaults = UserDefaults(suiteName: "HumTests-\(UUID().uuidString)")!
    let model = AppModel(container: Persistence.makeContainer(inMemory: true),
                         settings: DeviceSettings(defaults: defaults),
                         history: SpeechHistory(fileURL: nil))
    if starter { model.finishFirstRun(.starter) }
    return model
}

@MainActor
extension AppModel {
    /// Never force-unwrap in tests: a crash takes down the whole test host app.
    var home: Board { store.boards().first(where: \.isHome) ?? Board(name: "MISSING HOME", rows: 1, columns: 2) }

    /// "row,column" → label for every placed tile on a board.
    func layout(_ board: Board) -> [String: String] {
        Dictionary(uniqueKeysWithValues: board.placedTiles.map { ("\($0.row!),\($0.column!)", $0.label) })
    }
}
