// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftData

/// Create, rename, duplicate, delete and resize boards; choose the Home board.
struct BoardManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Board.createdAt) private var boards: [Board]

    @State private var newBoardName = ""
    @State private var newRows = 3
    @State private var newColumns = 4
    @State private var boardToDelete: Board?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Your boards") {
                    ForEach(boards) { board in
                        NavigationLink {
                            BoardDetailView(board: board, errorMessage: $errorMessage)
                        } label: {
                            HStack {
                                Label(board.name, systemImage: board.isHome ? "house.fill" : "square.grid.3x3")
                                Spacer()
                                Text("\(board.rows) × \(board.columns)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .contextMenu {
                            Button("Edit this board", systemImage: "pencil") {
                                model.editingBoardID = board.id
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
                    TextField("Board name, e.g. Food or Outside", text: $newBoardName)
                    GridSizePicker(rows: $newRows, columns: $newColumns)
                    Button("Make board", systemImage: "plus") {
                        let board = model.store.createBoard(name: newBoardName.trimmingCharacters(in: .whitespaces), rows: newRows, columns: newColumns)
                        newBoardName = ""
                        model.editingBoardID = board.id
                        dismiss()
                    }
                    .disabled(newBoardName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("New board")
                } footer: {
                    Text("To open it from another board, edit a tile and choose it under \"Opens a board\". Keep \"no\", \"stop\" and \"all done\" on Home too.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Boards")
            .onAppear {
                newRows = model.settings.newBoardRows
                newColumns = model.settings.newBoardColumns
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete \(boardToDelete?.name ?? "this board")?", isPresented: Binding(get: { boardToDelete != nil }, set: { if !$0 { boardToDelete = nil } }), titleVisibility: .visible) {
                Button("Delete board", role: .destructive) {
                    if let board = boardToDelete {
                        do { try model.store.delete(board) } catch { errorMessage = error.localizedDescription }
                    }
                    boardToDelete = nil
                }
            } message: {
                Text("Its tiles are deleted too. Tiles that opened this board will still speak. You can undo this.")
            }
            .alert("Can't do that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }
}

private struct BoardDetailView: View {
    let board: Board
    @Binding var errorMessage: String?
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
                    Label("This is the Home board", systemImage: "house.fill")
                } else {
                    Button("Make this the Home board", systemImage: "house") { model.store.setHome(board) }
                }
                Button("Duplicate board", systemImage: "plus.square.on.square") { model.store.duplicate(board) }
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
