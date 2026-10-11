// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
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
    @State private var newRows = 3
    @State private var newColumns = 4
    @State private var boardToDelete: Board?
    @State private var errorMessage: String?

    /// Boards some tile opens.
    private var reachable: Set<UUID> { Set(tiles.compactMap(\.linkedBoardID)) }

    /// Where "Make folder" puts the new folder tile: the board being edited, or Home.
    private var hostBoard: Board? {
        boards.first { $0.id == model.editingBoardID } ?? boards.first(where: \.isHome) ?? boards.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Home and folders") {
                    ForEach(boards) { board in
                        NavigationLink {
                            BoardDetailView(board: board, errorMessage: $errorMessage, onDelete: { boardToDelete = board })
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
                                Text("\(board.rows) × \(board.columns)").foregroundStyle(.secondary).monospacedDigit()
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
                    GridSizePicker(rows: $newRows, columns: $newColumns)
                    Button("Make folder", systemImage: "folder.badge.plus", action: makeFolder)
                        .disabled(newBoardName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("New folder")
                } footer: {
                    Text("Adds a folder tile to \(hostBoard?.name ?? "Home") in its first empty spot, then opens the new folder so you can fill it. Keep \"no\", \"stop\" and \"all done\" on Home too.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Home & folders")
            .onAppear {
                newRows = model.settings.newBoardRows
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
        let folder = model.store.addFolder(named: name, on: host, rows: newRows, columns: newColumns)
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
                            GridPreview(rows: board.rows, columns: board.columns).frame(width: 22, height: 22)
                            Text("\(board.rows) × \(board.columns)").monospacedDigit()
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
                    Button("Make this the Home board", systemImage: "house") { model.store.setHome(board) }
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

/// Rows × columns steppers with a tiny live preview.
struct GridSizePicker: View {
    @Binding var rows: Int
    @Binding var columns: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading) {
                Stepper("Rows: \(rows)", value: $rows, in: 1...8)
                Stepper("Columns: \(columns)", value: $columns, in: 1...8)
            }
            GridPreview(rows: rows, columns: columns)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
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
