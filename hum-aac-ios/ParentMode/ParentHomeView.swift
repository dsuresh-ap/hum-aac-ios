// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftData

/// Parent (edit) mode entry point. M1 keeps this small; M2 adds the full editor.
struct ParentHomeView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Board.createdAt) private var boards: [Board]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        model.rebuildSnapshot()
                        model.mode = .child
                    } label: {
                        Label("Back to the child's board", systemImage: "arrow.uturn.backward")
                    }
                    .accessibilityIdentifier("exitParentMode")
                }
                Section("Boards") {
                    ForEach(boards) { board in
                        HStack {
                            Label(board.name, systemImage: board.isHome ? "house" : "square.grid.3x3")
                            Spacer()
                            Text("\(board.placedTiles.count) tiles · \(board.rows) × \(board.columns)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("For developers") {
                    NavigationLink {
                        DeveloperLatencyView()
                    } label: {
                        Label("Tap-to-sound latency", systemImage: "stopwatch")
                    }
                    .accessibilityIdentifier("developerLatency")
                }
            }
            .navigationTitle("Grown-up settings")
        }
    }
}
