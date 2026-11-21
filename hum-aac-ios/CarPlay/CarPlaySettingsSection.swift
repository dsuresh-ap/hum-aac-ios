// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Settings → In the car: which board CarPlay shows on this iPhone (CarBoard.swift).
struct CarPlaySettingsSection: View {
    /// CarPlay only runs on iPhone.
    static var isShown: Bool {
        #if os(iOS)
        CarBoard.isAvailable && UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    @Environment(AppModel.self) private var model
    @Query(sort: \Board.createdAt) private var boards: [Board]

    /// Home first, then A→Z, like the board list.
    private var sorted: [Board] {
        boards.sorted { ($0.isHome ? 0 : 1, $0.name.lowercased()) < ($1.isHome ? 0 : 1, $1.name.lowercased()) }
    }

    /// The chosen board, if it still exists. `nil` shows Home.
    private var chosen: Board? { boards.first { $0.id == model.settings.carBoardID } }

    var body: some View {
        @Bindable var settings = model.settings
        Section {
            Picker("Board in the car", selection: Binding(
                get: { chosen.flatMap { $0.isHome ? nil : $0.id } },
                set: { settings.carBoardID = $0 })) {
                ForEach(sorted) { board in
                    // Home is the default: choosing it clears the choice.
                    Text(board.name).tag(board.isHome ? nil : Optional(board.id))
                }
            }
            if chosen == nil {
                Button("Make an “In the car” board", systemImage: "car") {
                    CarBoard.makeStarterBoard(in: model)
                }
            }
            if let board = chosen ?? boards.first(where: \.isHome), CarBoard.tilesLeftOut(on: board) > 0 {
                Text("Some tiles on this board don't fit in the car. It shows the first 8.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("In the car (CarPlay)")
        } footer: {
            Text("On a car's screen, Hum shows the first 8 tiles of this board and says them through the car's speakers. Folders don't open there. At a traffic stop, the driver can tap the car's screen instead of reaching for a phone.")
        }
    }
}
