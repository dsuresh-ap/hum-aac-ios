// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import HumConfig
import SwiftData

/// Home and folders: create, rename, duplicate, delete and resize them; choose the Home board.
///
/// In the parent UI every board except Home is a "folder". A folder no tile opens is flagged, because
/// the child can't reach it.
struct BoardManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Board.createdAt) private var boards: [Board]
    @Query private var tiles: [Tile]

    @State private var newBoardName = ""
    @State private var newColumns = 4
    @State private var boardToDelete: Board?
    @State private var errorMessage: String?
    @State private var search = ""

    /// Home first, then A→Z, filtered by the search field (a big import can add a hundred folders).
    private var listed: [Board] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return boards
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.isHome ? 0 : 1, $0.name.lowercased()) < ($1.isHome ? 0 : 1, $1.name.lowercased()) }
    }

    /// Boards some tile opens.
    private var reachable: Set<UUID> { Set(tiles.compactMap(\.linkedBoardID)) }

    /// Where "Make folder" puts the new folder tile: the board being edited, or Home.
    private var hostBoard: Board? {
        boards.first { $0.id == model.editingBoardID } ?? boards.first(where: \.isHome) ?? boards.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(listed) { board in
                        NavigationLink {
                            BoardDetailView(board: board, errorMessage: $errorMessage, onDelete: { boardToDelete = board },
                                            onMakeHome: { model.store.setHome(board) })
                        } label: {
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(board.name)
                                        if !board.isHome && !reachable.contains(board.id) {
                                            Text("No tile opens this folder yet").font(.caption).foregroundStyle(.orange)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: board.isHome ? "house.fill" : "folder")
                                }
                                Spacer()
                                Text("\(board.columns) across").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") {
                                model.editBoard(board.id)
                                dismiss()
                            }
                            Button("Duplicate", systemImage: "plus.square.on.square") { model.store.duplicate(board) }
                            if !board.isHome {
                                Button("Make Home board", systemImage: "house") { model.store.setHome(board) }
                                Button("Delete…", systemImage: "trash", role: .destructive) { boardToDelete = board }
                            }
                        }
                    }
                }

                Section {
                    TextField("Folder name, e.g. Food or Outside", text: $newBoardName)
                        .onSubmit(makeFolder)
                    GridSizePicker(columns: $newColumns)
                    Button("Make folder", systemImage: "folder.badge.plus", action: makeFolder)
                        .disabled(newBoardName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("New folder")
                } footer: {
                    Text("Adds a folder tile to \(hostBoard?.name ?? "Home") in its first empty spot, then opens the new folder so you can fill it.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Home & folders")
            .modifier(SearchWhenLong(isLong: boards.count > 12, text: $search))
            .onAppear {
                newColumns = model.settings.newBoardColumns
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete \(boardToDelete?.name ?? "this folder")?", isPresented: Binding(get: { boardToDelete != nil }, set: { if !$0 { boardToDelete = nil } }), titleVisibility: .visible) {
                Button("Delete folder", role: .destructive) {
                    if let board = boardToDelete {
                        do { try model.store.delete(board) } catch { errorMessage = error.localizedDescription }
                    }
                    boardToDelete = nil
                }
            } message: {
                Text("Its tiles are deleted too. Tiles that opened it will still speak. You can undo this.")
            }
            .alert("Can't do that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    /// Makes the folder and the tile that opens it, then opens the folder in the editor.
    private func makeFolder() {
        let name = newBoardName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let host = hostBoard else { return }
        let folder = model.store.addFolder(named: name, on: host, rows: newColumns == 1 ? 2 : 1, columns: newColumns)
        newBoardName = ""
        model.editBoard(host.id)
        model.openFolderInEditor(folder.id)
        dismiss()
    }
}

private struct BoardDetailView: View {
    let board: Board
    @Binding var errorMessage: String?
    let onDelete: () -> Void
    let onMakeHome: () -> Void
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var showGridSize = false

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name)
                    .onSubmit { if !name.isEmpty { model.store.rename(board, to: name) } }
            }
            Section {
                Button {
                    showGridSize = true
                } label: {
                    LabeledContent("Grid size") {
                        HStack(spacing: 8) {
                            Image(systemName: "square.grid.2x2")
                            Text("\(board.columns) across").monospacedDigit()
                        }
                    }
                }
            } footer: {
                Text("Show more or fewer tiles. Tiles always keep their places.")
            }
            Section {
                if board.isHome {
                    Label("This is the Home board. It opens first.", systemImage: "house.fill")
                } else {
                    Button("Make this the Home board", systemImage: "house", action: onMakeHome)
                }
                Button("Duplicate", systemImage: "plus.square.on.square") { model.store.duplicate(board) }
                if !board.isHome {
                    Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(board.name)
        .sheet(isPresented: $showGridSize) { GridSizeSheet(board: board) }
        .onAppear { name = board.name }
        .onDisappear { if !name.isEmpty, name != board.name { model.store.rename(board, to: name) } }
    }
}

/// A tile size slider: how many tiles go across, from what fits on this screen. Bigger tiles means fewer
/// across. That number is saved as the board's columns, so tiles never reflow when the screen turns or the
/// window changes. Rows come from the tiles: a board that's taller than the screen scrolls down.
struct GridSizePicker: View {
    @Binding var columns: Int
    /// The fewest columns allowed (a board's tiles need at least this many within the maximum rows).
    var minColumns = 1
    @Environment(AppModel.self) private var model

    /// The most columns the slider offers: as many as fit at a usable size on this screen. iPhone shows
    /// wide boards in pages, so it offers all 8. A board that already has more keeps its number.
    private var maxColumns: Int {
        let fitting = AppModel.isPhone
            ? HumValidator.columnRange.upperBound
            : GridMetrics.maxColumns(across: model.boardArea.width, spacing: Theme.gridSpacing)
        return max(fitting, columns, minColumns + 1, 2)
    }

    /// Bigger tiles to the right: the slider runs over column counts, reversed.
    private var size: Binding<Double> {
        Binding(get: { Double(maxColumns + 1 - columns) },
                set: { columns = maxColumns + 1 - Int($0.rounded()) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tile size")
            Slider(value: size, in: 1...Double(maxColumns + 1 - minColumns), step: 1) {
                Text("Tile size")
            } minimumValueLabel: {
                Image(systemName: "square.grid.4x3.fill").font(.caption).accessibilityLabel("Smaller")
            } maximumValueLabel: {
                Image(systemName: "square.grid.2x2.fill").font(.title3).accessibilityLabel("Bigger")
            }
            .accessibilityValue("\(columns) tile\(columns == 1 ? "" : "s") across")
            .accessibilityIdentifier("tileSize")
            Text("\(columns) tile\(columns == 1 ? "" : "s") across")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A search field, only once the list is long enough to need one.
private struct SearchWhenLong: ViewModifier {
    let isLong: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if isLong {
            content.searchable(text: $text, prompt: "Find a folder")
        } else {
            content
        }
    }
}

struct GridPreview: View {
    let rows: Int
    let columns: Int

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 2) {
                    ForEach(0..<columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.5))
                    }
                }
            }
        }
    }
}
