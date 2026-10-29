// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Everything said recently, grouped by day, for a parent to look back on (e.g. to notice new gestalts
/// or what the child asked for while you were out of the room). Stays on this device.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        @Bindable var settings = model.settings
        let days = Dictionary(grouping: model.history.entries.reversed()) { Calendar.current.startOfDay(for: $0.date) }
        NavigationStack {
            List {
                Section {
                    Toggle("Show the history box on the child's screen", isOn: $settings.showHistory)
                } footer: {
                    Text("A small row above the tiles shows what was said last, so you can catch up if you missed it. Tapping a phrase there says it again.")
                }

                if model.history.entries.isEmpty {
                    Section {
                        Text("Nothing yet. What your child says will appear here.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    Section(day.formatted(.dateTime.weekday(.wide).month().day())) {
                        ForEach(days[day] ?? []) { entry in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Theme.tileColor(function: entry.function, hex: entry.colorHex))
                                    .frame(width: 12, height: 12)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.spokenText)
                                    if entry.count > 1 {
                                        Text("\(entry.count) times in a row").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(entry.date.formatted(date: .omitted, time: .shortened))
                                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                                Button {
                                    model.replay(entry)
                                } label: {
                                    Image(systemName: "play.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Say “\(entry.spokenText)” again")
                                .help("Say it again")
                            }
                        }
                    }
                }

                // At the bottom, away from Done, so a quick tap on Done never lands on it (BUGS.md, HUM-026).
                if !model.history.entries.isEmpty {
                    Section {
                        Button("Clear history…", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { model.history.clear() }
            } message: {
                Text("This removes the list of what was said on this device. It can't be undone.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }
}
