// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Bigger or smaller tiles on a board: a tile size slider (how many go across).
///
/// A new tile size re-flows the tiles in reading order, so the order the child knows stays the same, and
/// the board gets the rows it needs. A taller board scrolls, so no tile is ever cut off or sent to the tray.
struct GridSizeSheet: View {
    let board: Board
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var columns = 3
    @State private var confirmDiscard = false

    /// Where every tile goes at the picked size.
    private var reflow: (spots: [UUID: (row: Int, column: Int)], rows: Int) { model.store.reflowedSpots(board, columns: columns) }
    /// How many tiles change spot at the picked size.
    private var moving: Int { board.placedTiles.filter { t in reflow.spots[t.id].map { $0 != (t.row!, t.column!) } ?? false }.count }
    private var changed: Bool { columns != board.columns }
    /// The rows the board gets at the picked size (at least 2 spots).
    private var rows: Int { max(reflow.rows, columns == 1 ? 2 : 1) }

    var body: some View {
        NavigationStack {
            Form {
                // The controls first, so the preview below changes while the parent drags.
                Section {
                    GridSizePicker(columns: $columns, minColumns: model.store.minimumColumns(board))
                } footer: {
                    Text(footer)
                }

                Section {
                    ScreenPreview(board: board, spots: reflow.spots, rows: rows, columns: columns, area: model.boardArea)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Tile size for \(board.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if changed { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .disabled(!changed)
                        .accessibilityIdentifier("applyGridSize")
                }
            }
            .interactiveDismissDisabled(changed)
            .confirmationDialog("Keep the old size?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard new size", role: .destructive) { dismiss() }
                Button("Apply \(columns) across") { apply() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("You picked \(columns) tiles across but haven't applied it.")
            }
            .onAppear { columns = board.columns }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private var footer: String {
        var text = moving > 0
            ? String(localized: "\(moving) tiles move. The order stays the same: left to right, then top to bottom. Your child may need time to find them again.")
            : String(localized: "No tiles move.")
        // The grid is shared by every device. iPhone shows boards wider than 4 tiles as pages.
        if AppModel.isPhone && columns > PhoneLayout.columns {
            text += " " + String(localized: "On iPhone, boards wider than \(PhoneLayout.columns) tiles are shown as pages.")
        }
        return text
    }

    private func apply() {
        model.store.setColumns(board, columns)
        dismiss()
    }
}

/// Live preview of the child's screen at the new size: the screen's own shape, tiles at their new size
/// with their colors and pictures, and the rows the child scrolls to drawn faded below the screen's edge.
private struct ScreenPreview: View {
    let board: Board
    /// Where each tile goes at the new size (from `BoardStore.reflowedSpots`).
    let spots: [UUID: (row: Int, column: Int)]
    let rows: Int
    let columns: Int
    /// The child's board area on this device (`AppModel.boardArea`). Zero until a board has been shown.
    let area: CGSize

    /// The most room the little screen gets (a phone's tall screen is limited by height).
    private let maxSize = CGSize(width: 280, height: 220)
    /// How much of the scrolled part shows below the screen, as a share of the screen's height.
    private let belowShare: CGFloat = 0.6

    var body: some View {
        let screen = area == .zero ? CGSize(width: 1024, height: 700) : area
        let scale = min(maxSize.width / screen.width, maxSize.height / screen.height)
        let width = screen.width * scale
        let spacing = Theme.gridSpacing
        let layout = GridMetrics.layout(in: screen, rows: rows, columns: columns, spacing: spacing)
        let tile = CGSize(width: layout.tileWidth * scale, height: layout.tileHeight * scale)
        let gap = spacing * scale
        let screenHeight = screen.height * scale
        let contentHeight = CGFloat(rows) * tile.height + CGFloat(rows - 1) * gap
        let shownHeight = min(contentHeight, screenHeight * (1 + belowShare))
        let tiles = Dictionary(board.placedTiles.compactMap { t in spots[t.id].map { ("\($0.row),\($0.column)", t) } },
                               uniquingKeysWith: { a, _ in a })

        VStack(spacing: 10) {
            ZStack(alignment: .top) {
                VStack(spacing: gap) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: gap) {
                            ForEach(0..<columns, id: \.self) { c in
                                cell(tiles["\(r),\(c)"], size: tile)
                            }
                        }
                    }
                }
                .frame(width: width, height: shownHeight, alignment: .top)
                .clipped()
                // Below the screen's edge: faded, and fading out, so it reads as "scroll to see".
                .mask {
                    VStack(spacing: 0) {
                        Rectangle().frame(height: min(screenHeight, shownHeight))
                        if shownHeight > screenHeight {
                            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        }
                    }
                }
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.ink.opacity(0.5), lineWidth: 2)
                    .frame(width: width + 12, height: screenHeight + 12)
                    .offset(y: -6)
            }
            .padding(.top, 6)
            .frame(height: shownHeight + 6, alignment: .top)

            if layout.scrolls {
                Label("Faded rows are below the screen. Your child scrolls down to reach them.", systemImage: "arrow.down")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(layout: layout))
        .accessibilityIdentifier("gridSizePreview")
    }

    @ViewBuilder
    private func cell(_ tile: Tile?, size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(size.width, size.height) * 0.18, style: .continuous)
        if let tile {
            shape.fill(Theme.tileColor(function: tile.function, hex: tile.colorHex))
                .overlay {
                    if let symbol = tile.symbol, !symbol.isEmpty {
                        Text(symbol).font(.system(size: min(size.width, size.height) * 0.5))
                    }
                }
                .frame(width: size.width, height: size.height)
        } else {
            shape.strokeBorder(Theme.ink.opacity(0.18), lineWidth: 1)
                .frame(width: size.width, height: size.height)
        }
    }

    private func accessibilitySummary(layout: GridMetrics.Layout) -> String {
        var text = String(localized: "\(columns) tiles across.") + " " + String(localized: "\(rows) rows.")
        if layout.scrolls, area != .zero {
            let visible = GridMetrics.visibleRows(in: area, rows: rows, columns: columns, spacing: Theme.gridSpacing)
            text += " " + String(localized: "\(visible) rows fit on the screen. Your child scrolls to reach the rest.")
        }
        return text
    }
}
