// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftData
import ImageIO

/// Parent (edit) mode: the same grid the child sees, with edit affordances.
///
/// Tap an empty spot to add a tile, tap a tile to edit it, drag a tile to move it. Tiles only move when
/// a parent drags them.
struct ParentEditorView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Board.createdAt) private var boards: [Board]

    @State private var editor: TileEditorRequest?
    @State private var showBoards = false
    @State private var showSettings = false
    @State private var showSharing = false
    @State private var showGuidedAccessTip = false
    @State private var errorMessage: String?

    private var board: Board? {
        boards.first { $0.id == model.editingBoardID } ?? boards.first(where: \.isHome) ?? boards.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let board {
                    VStack(spacing: 0) {
                        EditBand(boardName: board.name)
                        EditGrid(board: board, editor: $editor, errorMessage: $errorMessage)
                            .padding(Theme.gridPadding)
                        if !board.unplacedTiles.isEmpty {
                            UnplacedTray(board: board, editor: $editor)
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No boards yet", systemImage: "square.grid.3x3")
                    } actions: {
                        Button("Make a board") { showBoards = true }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(board?.name ?? "Boards")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .sheet(item: $editor) { request in
                TileEditorSheet(request: request)
            }
            .sheet(isPresented: $showBoards) { BoardManagerView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showSharing) { SetupSharingView() }
            .alert("Can't do that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Tip: lock the app with Guided Access", isPresented: $showGuidedAccessTip) {
                Button("Got it", role: .cancel) { model.settings.hasSeenGuidedAccessTip = true }
            } message: {
                Text("To keep your child inside Hum, turn on Guided Access in Settings → Accessibility → Guided Access. Then triple-click the side (or Home) button while Hum is open.")
            }
            .onAppear {
                #if os(iOS)
                if !model.settings.hasSeenGuidedAccessTip { showGuidedAccessTip = true }
                #endif
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                model.mode = .child
            } label: {
                Label("Done", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityIdentifier("exitParentMode")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Board", selection: Binding(get: { board?.id }, set: { model.editingBoardID = $0 })) {
                    ForEach(boards) { b in
                        Label(b.name, systemImage: b.isHome ? "house" : "square.grid.3x3").tag(Optional(b.id))
                    }
                }
                Divider()
                Button("Manage boards…", systemImage: "rectangle.stack") { showBoards = true }
            } label: {
                Label("Boards", systemImage: "rectangle.stack")
            }
            .accessibilityIdentifier("boardsMenu")

            Button {
                model.store.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!(model.store.undoManager?.canUndo ?? false))
            .keyboardShortcut("z", modifiers: .command)

            Button {
                showSharing = true
            } label: {
                Label("Setup & sharing", systemImage: "square.and.arrow.up.on.square")
            }
            .accessibilityIdentifier("setupSharing")

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("settings")
        }
    }
}

/// What the tile editor sheet is editing.
struct TileEditorRequest: Identifiable {
    enum Kind { case new(boardID: UUID, row: Int, column: Int), edit(tileID: UUID) }
    let id = UUID()
    let kind: Kind
}

/// The board grid in edit mode.
private struct EditGrid: View {
    let board: Board
    @Binding var editor: TileEditorRequest?
    @Binding var errorMessage: String?
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let spacing = Theme.gridSpacing
            let width = (geo.size.width - spacing * CGFloat(board.columns - 1)) / CGFloat(board.columns)
            let height = (geo.size.height - spacing * CGFloat(board.rows - 1)) / CGFloat(board.rows)
            let byPosition = Dictionary(board.placedTiles.map { ("\($0.row!),\($0.column!)", $0) }, uniquingKeysWith: { a, _ in a })
            VStack(spacing: spacing) {
                if min(width, height) < 88 {
                    Text("Tiles are smaller than 88 points on this screen. Consider fewer rows or columns, or a sub-board.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(0..<board.rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<board.columns, id: \.self) { column in
                            slot(tile: byPosition["\(row),\(column)"], row: row, column: column)
                                .frame(width: max(width, 0), height: max(height, 0))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func slot(tile: Tile?, row: Int, column: Int) -> some View {
        Group {
            if let tile {
                EditTileCard(tile: tile)
                    .onTapGesture { editor = TileEditorRequest(kind: .edit(tileID: tile.id)) }
                    .draggable(tile.id.uuidString)
                    .accessibilityHint("Double-tap to edit. Drag to move.")
            } else {
                Button {
                    editor = TileEditorRequest(kind: .new(boardID: board.id, row: row, column: column))
                } label: {
                    RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .foregroundStyle(Theme.ink.opacity(0.25))
                        .overlay {
                            Label("Add", systemImage: "plus")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Theme.ink.opacity(0.45))
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a tile here, row \(row + 1), column \(column + 1)")
                .accessibilityIdentifier("emptySlot.\(row).\(column)")
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)),
                  let dragged = (board.tiles ?? []).first(where: { $0.id == id }) else { return false }
            model.store.move(dragged, to: row, column: column, on: board)
            return true
        }
    }
}

/// A tile as shown in edit mode: the child's tile, plus a pencil, hidden state, and a small camera mark
/// when it still uses a placeholder emoji instead of a real photo.
struct EditTileCard: View {
    let tile: Tile

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            VStack(spacing: 4) {
                Group {
                    if let data = tile.imageData, let image = PlatformImage.thumbnail(data) {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(.rect(cornerRadius: Theme.tileCorner * 0.6, style: .continuous))
                    } else {
                        Text(tile.symbol ?? "")
                            .font(.system(size: size * 0.36))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                Text(tile.label)
                    .font(.system(size: max(13, size * 0.11), weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .padding(10)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Theme.tileColor(function: tile.function, hex: tile.colorHex), in: .rect(cornerRadius: Theme.tileCorner, style: .continuous))
            .opacity(tile.isHidden ? 0.45 : 1)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    if tile.isHidden { Image(systemName: "eye.slash") }
                    if tile.imageData == nil { Image(systemName: "camera").accessibilityLabel("No photo yet") }
                    if tile.audioData != nil { Image(systemName: "waveform").accessibilityLabel("Has a recording") }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink.opacity(0.45))
                .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: tile.linkedBoardID != nil ? "folder.fill" : "pencil")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.ink.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .background(.background.opacity(0.6), in: .circle)
                    .padding(8)
            }
        }
        .contentShape(.rect(cornerRadius: Theme.tileCorner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.label). Says: \(tile.spokenText)\(tile.isHidden ? ". Hidden" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("editTile.\(tile.label)")
    }
}

/// Always-visible reminder that this is the grown-up editing view, with the three things you can do.
private struct EditBand: View {
    let boardName: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "pencil.and.outline").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Editing \(boardName)")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                Text("Tap a tile to change it, tap + to add one, or drag a tile to move it. Your child sees changes when you tap Done.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gridPadding + 4)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.editBand)
    }
}

/// New tiles that couldn't go where an import asked. The parent drags each one to a spot.
private struct UnplacedTray: View {
    let board: Board
    @Binding var editor: TileEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(board.unplacedTiles.count) new tile\(board.unplacedTiles.count == 1 ? "" : "s") need a spot. Drag \(board.unplacedTiles.count == 1 ? "it" : "each one") onto the board.")
                .font(.callout.weight(.semibold))
            ScrollView(.horizontal) {
                HStack(spacing: Theme.gridSpacing) {
                    ForEach(board.unplacedTiles) { tile in
                        EditTileCard(tile: tile)
                            .frame(width: 110, height: 100)
                            .draggable(tile.id.uuidString)
                            .onTapGesture { editor = TileEditorRequest(kind: .edit(tileID: tile.id)) }
                    }
                }
            }
        }
        .padding(Theme.gridPadding)
        .background(Theme.chrome)
    }
}

enum PlatformImage {
    /// Small decoded preview for edit mode.
    static func thumbnail(_ data: Data, maxPixels: Int = 400) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
