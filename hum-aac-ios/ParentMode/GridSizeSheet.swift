// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Show more or fewer tiles on a board.
///
/// Every tile keeps its exact row and column (motor planning). A bigger grid just adds empty spots.
/// A smaller grid only removes spots; if tiles sit in those spots, the parent is told which ones and can
/// choose to put them in the "needs a spot" tray. They're never deleted, and nothing else moves.
struct GridSizeSheet: View {
    let board: Board
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rows = 3
    @State private var columns = 3
    @State private var confirmCut = false
    @State private var confirmDiscard = false
    @State private var errorMessage: String?

    static let presets: [(Int, Int)] = [(2, 2), (2, 3), (3, 3), (3, 4), (4, 5), (5, 6), (6, 8)]

    private var cutOff: [Tile] { model.store.tilesCutOff(board, rows: rows, columns: columns) }
    private var changed: Bool { rows != board.rows || columns != board.columns }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PreviewGrid(board: board, rows: rows, columns: columns)
                            .frame(width: 220, height: 220)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Quick sizes (rows × columns)") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(Self.presets.indices, id: \.self) { i in
                                let (r, c) = Self.presets[i]
                                let selected = r == rows && c == columns
                                Button {
                                    rows = r
                                    columns = c
                                } label: {
                                    VStack(spacing: 6) {
                                        GridPreview(rows: r, columns: c).frame(width: 44, height: 44)
                                        Text("\(r) × \(c)").font(.callout.weight(.semibold)).monospacedDigit()
                                    }
                                    .padding(10)
                                    .background(selected ? Color.accentColor.opacity(0.18) : Theme.chrome, in: .rect(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(r) rows, \(c) columns")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                }

                Section {
                    Stepper("Rows: \(rows)", value: $rows, in: 1...8)
                    Stepper("Columns: \(columns)", value: $columns, in: 1...8)
                } footer: {
                    Text(footer)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Grid size for \(board.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if changed { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .disabled(!changed || rows * columns < 2)
                        .accessibilityIdentifier("applyGridSize")
                }
            }
            .interactiveDismissDisabled(changed)
            .confirmationDialog("Keep the old size?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard new size", role: .destructive) { dismiss() }
                Button("Apply \(rows) × \(columns)") { apply() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("You picked \(rows) × \(columns) but haven't applied it.")
            }
            .confirmationDialog(cutTitle, isPresented: $confirmCut, titleVisibility: .visible) {
                Button("Move them to “needs a spot”") { apply(moveCutOff: true) }
                Button("Keep the current size", role: .cancel) {}
            } message: {
                Text("\(cutOff.map { "“\($0.label)”" }.joined(separator: ", ")) won't fit. They'll wait in the tray below the board until you place them. Every other tile stays exactly where it is.")
            }
            .alert("Can't change the size", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .onAppear {
                rows = board.rows
                columns = board.columns
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private var footer: String {
        if rows * columns < 2 { return "A board needs at least 2 spots." }
        if !cutOff.isEmpty {
            return "\(cutOff.count) tile\(cutOff.count == 1 ? "" : "s") won't fit this size (shown with a dashed outline)."
        }
        let total = rows * columns
        let base = "\(total) spots. Tiles keep their places: a bigger grid adds empty spots at the right and bottom."
        // The grid is shared by every device; shrinking it to fit a phone isn't needed any more.
        guard AppModel.isPhone else { return base }
        return base + " This size is for iPad and Mac too. On iPhone, boards wider than \(PhoneLayout.columns) or taller than \(PhoneLayout.rows) use a phone layout instead, so you don't need to shrink them here."
    }

    private var cutTitle: String { "\(cutOff.count) tile\(cutOff.count == 1 ? "" : "s") won't fit" }

    private func apply(moveCutOff: Bool = false) {
        if !cutOff.isEmpty && !moveCutOff {
            confirmCut = true
            return
        }
        do {
            try model.store.resize(board, rows: rows, columns: columns, moveCutOffToTray: moveCutOff)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Live preview: existing tiles in their real spots (colored), empty spots outlined, and tiles that
/// would not fit drawn dashed outside the new grid.
private struct PreviewGrid: View {
    let board: Board
    let rows: Int
    let columns: Int

    var body: some View {
        let shownRows = max(rows, board.rows)
        let shownColumns = max(columns, board.columns)
        let tiles = Dictionary(board.placedTiles.map { ("\($0.row!),\($0.column!)", $0) }, uniquingKeysWith: { a, _ in a })
        VStack(spacing: 3) {
            ForEach(0..<shownRows, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(0..<shownColumns, id: \.self) { c in
                        let inside = r < rows && c < columns
                        let tile = tiles["\(r),\(c)"]
                        RoundedRectangle(cornerRadius: 4)
                            .fill(tile.map { Theme.tileColor(function: $0.function, hex: $0.colorHex) } ?? Color.clear)
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: inside ? [] : [3, 3]))
                                    .foregroundStyle(Theme.ink.opacity(inside ? 0.25 : (tile == nil ? 0 : 0.6)))
                            }
                            .opacity(inside || tile != nil ? 1 : 0)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
