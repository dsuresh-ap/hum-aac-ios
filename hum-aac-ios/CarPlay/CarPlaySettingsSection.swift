// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Settings → In the car: which boards CarPlay shows on this iPhone (CarBoard.swift), whether each
/// phrase shows big, and the About me card (AboutMeCard.swift).
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

    /// The chosen boards that still exist, in the car's tab order.
    private var chosen: [Board] {
        model.settings.carBoardIDs.compactMap { id in boards.first { $0.id == id } }
    }

    /// Boards that could still be added, Home first, then A→Z, like the board list.
    private var addable: [Board] {
        let picked = Set(model.settings.carBoardIDs)
        return boards.filter { !picked.contains($0.id) }
            .sorted { ($0.isHome ? 0 : 1, $0.name.lowercased()) < ($1.isHome ? 0 : 1, $1.name.lowercased()) }
    }

    private var openable: Set<UUID> { Set(boards.filter { !CarBoard.tiles(on: $0).isEmpty }.map(\.id)) }

    var body: some View {
        @Bindable var settings = model.settings
        Section {
            if chosen.isEmpty {
                if let home = boards.first(where: \.isHome) {
                    row(for: home, note: String(localized: "Shown until you add a board."))
                }
                Button("Make “Traffic stop” and “After a crash” boards", systemImage: "car") {
                    CarBoard.makeStarterBoards(in: model)
                }
            } else {
                ForEach(chosen) { board in
                    row(for: board, note: nil)
                        .contextMenu {
                            Button("Remove from the car", systemImage: "minus.circle", role: .destructive) { remove(board.id) }
                        }
                }
                .onMove { from, to in
                    var ids = chosen.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    settings.carBoardIDs = ids
                }
                .onDelete { offsets in
                    for id in offsets.map({ chosen[$0].id }) { remove(id) }
                }
            }
            if chosen.count < CarBoard.maximumBoards && !addable.isEmpty {
                Menu {
                    ForEach(addable) { board in
                        Button(board.name) { settings.carBoardIDs = chosen.map(\.id) + [board.id] }
                    }
                } label: {
                    Label("Add a board", systemImage: "plus.circle")
                }
            }
            Toggle("Show each phrase big", isOn: $settings.carShowsEachPhrase)
            NavigationLink {
                AboutMeCardEditor()
            } label: {
                LabeledContent("About me card") {
                    Text(model.settings.aboutMe.isEmpty ? String(localized: "Off") : String(localized: "On"))
                }
            }
        } header: {
            Text("In the car (CarPlay)")
        } footer: {
            Text("Each board is a tab on the car's screen with its first 8 tiles. Folder tiles open their folder. Hum speaks through the car's speakers. “Show each phrase big” puts each phrase on the screen after it's said, for someone outside the window to read. At a traffic stop, the driver can tap the car's screen instead of reaching for a phone.")
        }
    }

    private func row(for board: Board, note: String?) -> some View {
        let leftOut = CarBoard.tilesLeftOut(on: board, openable: openable.subtracting([board.id]))
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(board.name)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if leftOut > 0 {
                    Text("\(leftOut) tiles don't fit. The car shows the first 8.").font(.caption).foregroundStyle(.orange)
                }
            }
        } icon: {
            Image(systemName: board.isHome ? "house.fill" : "car")
        }
    }

    private func remove(_ id: UUID) {
        model.settings.carBoardIDs.removeAll { $0 == id }
    }
}

/// Settings → In the car → About me card. What an officer or helper reads on the car's screen.
struct AboutMeCardEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        let unused = AboutMeCard.suggestions.filter { !settings.aboutMe.lines.contains($0) }
        Form {
            Section {
                TextField("Name", text: $settings.aboutMe.name)
                    .textContentType(.name)
            } footer: {
                Text("The card is a tab on the car's screen. “Say this” reads it out. Leave everything empty to hide the tab.")
            }
            Section {
                ForEach($settings.aboutMe.lines.indices, id: \.self) { index in
                    TextField("A line on the card", text: $settings.aboutMe.lines[index], axis: .vertical)
                }
                .onDelete { settings.aboutMe.lines.remove(atOffsets: $0) }
                .onMove { settings.aboutMe.lines.move(fromOffsets: $0, toOffset: $1) }
                if settings.aboutMe.lines.count < AboutMeCard.maximumLines {
                    Button("Add a line", systemImage: "plus.circle") { settings.aboutMe.lines.append("") }
                    if !unused.isEmpty {
                        Menu {
                            ForEach(unused, id: \.self) { line in
                                Button(line) { settings.aboutMe.lines.append(line) }
                            }
                        } label: {
                            Label("Add a suggested line", systemImage: "text.badge.plus")
                        }
                    }
                }
            } header: {
                Text("What the card says")
            } footer: {
                Text("Up to \(AboutMeCard.maximumLines) lines, in the driver's own words.")
            }
            Section {
                TextField("Name", text: $settings.aboutMe.contactName)
                    .textContentType(.name)
                TextField("Phone number", text: $settings.aboutMe.contactPhone)
                    .textContentType(.telephoneNumber)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    #endif
            } header: {
                Text("Emergency contact")
            } footer: {
                Text("The card stays on this iPhone. It isn't synced or included when you export boards.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About me card")
    }
}
