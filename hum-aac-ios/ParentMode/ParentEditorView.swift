// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftData
import ImageIO

/// Parent (edit) mode: the same grid the child sees, with edit affordances.
///
/// Tap an empty spot to add a tile (or a folder), tap a tile to edit it, drag a tile to move it.
/// Tiles only move when a parent drags them or chooses "Move to folder".
struct ParentEditorView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Board.createdAt) private var boards: [Board]

    @State private var editor: TileEditorRequest?
    @State private var showBoards = false
    @State private var showSettings = false
    @State private var showSharing = false
    @State private var showGuidedAccessTip = false
    @State private var showGridSize = false
    @State private var showHistory = false
    @State private var showAI = false
    @State private var showPaste = false
    @State private var errorMessage: String?
    @State private var notice: EditNotice?

    private var board: Board? {
        boards.first { $0.id == model.editingBoardID } ?? boards.first(where: \.isHome) ?? boards.first
    }

    private var anySheet: Bool {
        editor != nil || showBoards || showSettings || showSharing || showGridSize || showHistory || showAI || showPaste
    }

    var body: some View {
        NavigationStack {
            Group {
                if let board {
                    VStack(spacing: 0) {
                        EditBand(
                            board: board,
                            parentName: model.editPath.last.flatMap { id in boards.first { $0.id == id }?.name },
                            onBack: model.backInEditor,
                            onGridSize: { showGridSize = true })
                        EditGrid(board: board, editor: $editor, errorMessage: $errorMessage, notice: $notice,
                                 openFolder: model.openFolderInEditor)
                            .padding(Theme.gridPadding)
                        if !board.unplacedTiles.isEmpty {
                            UnplacedTray(board: board, editor: $editor)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let notice { NoticeBanner(notice: notice, onOpen: { model.openFolderInEditor($0); self.notice = nil }) }
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
            .sheet(isPresented: $showGridSize) { if let board { GridSizeSheet(board: board) } }
            .sheet(isPresented: $showHistory) { HistoryView() }
            .sheet(isPresented: $showAI) { AIHelperView() }
            .sheet(isPresented: $showPaste) { PastePhrasesSheet() }
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
            .task(id: notice?.id) {
                guard notice != nil else { return }
                try? await Task.sleep(for: .seconds(5))
                notice = nil
            }
            // Menu-bar / hardware-keyboard commands. Off while a sheet is up, so ⌘N never opens a
            // second editor behind the first.
            .focusedSceneValue(\.editorCommands, anySheet ? nil : commands)
        }
    }

    private var commands: EditorCommands {
        EditorCommands(
            newTile: { addNew(folder: false) },
            newFolder: { addNew(folder: true) },
            pastePhrases: { showPaste = true },
            aiHelper: AIHelper.isSupportedOnThisDevice ? { showAI = true } : nil,
            gridSize: { showGridSize = true },
            foldersList: { showBoards = true },
            back: model.editPath.isEmpty ? nil : { model.backInEditor() },
            home: { model.editBoard(boards.first(where: \.isHome)?.id) },
            history: { showHistory = true },
            sharing: { showSharing = true },
            settings: { showSettings = true },
            done: { model.mode = .child })
    }

    /// New tile or folder in the first empty spot of this board.
    private func addNew(folder: Bool) {
        guard let board else { return }
        guard let spot = model.store.firstEmptySpot(on: board) else {
            errorMessage = "\(board.name) is full. Make the grid bigger (the size at the top right) or hide a tile you don't need."
            return
        }
        editor = TileEditorRequest(kind: .new(boardID: board.id, row: spot.row, column: spot.column), startsAsFolder: folder)
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
                Button("New tile", systemImage: "plus.square") { addNew(folder: false) }
                Button("New folder", systemImage: "folder.badge.plus") { addNew(folder: true) }
                Button("Paste phrases…", systemImage: "list.bullet.rectangle") { showPaste = true }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Add a tile, a folder, or many phrases at once")
            .accessibilityIdentifier("addMenu")

            Menu {
                Picker("Board", selection: Binding(get: { board?.id }, set: { model.editBoard($0) })) {
                    ForEach(boards) { b in
                        Label(b.name, systemImage: b.isHome ? "house" : "folder").tag(Optional(b.id))
                    }
                }
                Divider()
                Button("Home & folders…", systemImage: "rectangle.stack") { showBoards = true }
            } label: {
                Label("Home & folders", systemImage: "rectangle.stack")
            }
            .accessibilityIdentifier("boardsMenu")

            Button {
                model.store.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!(model.store.undoManager?.canUndo ?? false))
            .keyboardShortcut("z", modifiers: .command)

            // Only on devices with Apple Intelligence (hidden elsewhere, as the spec asks).
            if AIHelper.isSupportedOnThisDevice {
                Button {
                    showAI = true
                } label: {
                    Label("Help me set up", systemImage: "sparkles")
                }
                .help("Suggest tiles from what your child says")
                .accessibilityIdentifier("aiHelper")
            }

            Button {
                showHistory = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("history")

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
    /// "New folder": the sheet asks for a name first and makes the folder on Save.
    var startsAsFolder = false
}

/// A short message after a move, e.g. "Moved “juice” into Food." with a button to open the folder.
struct EditNotice: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let folderID: UUID?
}

private struct NoticeBanner: View {
    let notice: EditNotice
    let onOpen: (UUID) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
            Text(notice.text).font(.callout.weight(.semibold))
            if let id = notice.folderID {
                Button("Open folder") { onOpen(id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: .capsule)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

/// The board grid in edit mode.
private struct EditGrid: View {
    let board: Board
    @Binding var editor: TileEditorRequest?
    @Binding var errorMessage: String?
    @Binding var notice: EditNotice?
    let openFolder: (UUID) -> Void
    @Environment(AppModel.self) private var model
    @Query(sort: \Board.createdAt) private var boards: [Board]

    var body: some View {
        GeometryReader { geo in
            let spacing = Theme.gridSpacing
            let width = (geo.size.width - spacing * CGFloat(board.columns - 1)) / CGFloat(board.columns)
            let height = (geo.size.height - spacing * CGFloat(board.rows - 1)) / CGFloat(board.rows)
            let byPosition = Dictionary(board.placedTiles.map { ("\($0.row!),\($0.column!)", $0) }, uniquingKeysWith: { a, _ in a })
            VStack(spacing: spacing) {
                if min(width, height) < 88 {
                    Text("Tiles are smaller than 88 points on this screen. Consider fewer rows or columns, or a folder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(0..<board.rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<board.columns, id: \.self) { column in
                            slot(tile: byPosition["\(row),\(column)"], row: row, column: column, roomy: height >= 120 && width >= 120)
                                .frame(width: max(width, 0), height: max(height, 0))
                        }
                    }
                }
            }
        }
    }

    /// Folders a tile could move into: every board except this one and the folder the tile itself opens.
    private func destinations(for tile: Tile) -> [Board] {
        boards.filter { $0.id != board.id && $0.id != tile.linkedBoardID }
    }

    private func moveIntoFolder(_ tile: Tile, _ folder: Board) {
        let placed = model.store.moveToBoard(tile, folder)
        withAnimation {
            notice = EditNotice(
                text: placed ? "Moved “\(tile.label)” into \(folder.name)." : "Moved “\(tile.label)” into \(folder.name). It's full, so it waits for a spot there.",
                folderID: folder.id)
        }
    }

    @ViewBuilder
    private func slot(tile: Tile?, row: Int, column: Int, roomy: Bool) -> some View {
        Group {
            if let tile {
                EditTileCard(tile: tile,
                             onOpenFolder: tile.linkedBoardID.map { id in { openFolder(id) } },
                             onDropIntoFolder: tile.linkedBoardID.flatMap { id in boards.first { $0.id == id } }.map { folder in
                                 { droppedID in
                                     guard droppedID != tile.id, let dragged = (board.tiles ?? []).first(where: { $0.id == droppedID }) else { return false }
                                     moveIntoFolder(dragged, folder)
                                     return true
                                 }
                             })
                    .onTapGesture { editor = TileEditorRequest(kind: .edit(tileID: tile.id)) }
                    .draggable(tile.id.uuidString)
                    .contextMenu {
                        Button("Edit tile", systemImage: "pencil") { editor = TileEditorRequest(kind: .edit(tileID: tile.id)) }
                        if let link = tile.linkedBoardID {
                            Button("Open folder", systemImage: "folder") { openFolder(link) }
                        }
                        let targets = destinations(for: tile)
                        if !targets.isEmpty {
                            Menu("Move to folder", systemImage: "folder.badge.gearshape") {
                                ForEach(targets) { folder in
                                    Button(folder.isHome ? "\(folder.name) (Home)" : folder.name) { moveIntoFolder(tile, folder) }
                                }
                            }
                        }
                        Button(tile.isHidden ? "Show tile" : "Hide tile", systemImage: tile.isHidden ? "eye" : "eye.slash") {
                            model.store.setHidden(tile, !tile.isHidden)
                        }
                        Divider()
                        Button("Delete tile", systemImage: "trash", role: .destructive) { model.store.delete(tile) }
                    }
                    .accessibilityHint("Double-tap to edit. Drag to move.")
            } else {
                EmptySlot(row: row, column: column, roomy: roomy,
                          add: { folder in editor = TileEditorRequest(kind: .new(boardID: board.id, row: row, column: column), startsAsFolder: folder) })
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

/// An empty spot: tap to add a tile here. Roomy spots also offer "Folder"; every spot has both in
/// its context menu.
private struct EmptySlot: View {
    let row: Int
    let column: Int
    let roomy: Bool
    let add: (_ folder: Bool) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Button {
                add(false)
            } label: {
                RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(Theme.ink.opacity(0.25))
                    .overlay {
                        Label("Tile", systemImage: "plus")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.ink.opacity(0.45))
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a tile here, row \(row + 1), column \(column + 1)")
            .accessibilityIdentifier("emptySlot.\(row).\(column)")

            if roomy {
                Button {
                    add(true)
                } label: {
                    Label("Folder", systemImage: "folder.badge.plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink.opacity(0.55))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.ink.opacity(0.06), in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
                .accessibilityLabel("Add a folder here, row \(row + 1), column \(column + 1)")
            }
        }
        .contextMenu {
            Button("New tile here", systemImage: "plus.square") { add(false) }
            Button("New folder here", systemImage: "folder.badge.plus") { add(true) }
        }
    }
}

/// A tile as shown in edit mode: the child's tile, plus a pencil, hidden state, and a small camera mark
/// when it still uses a placeholder emoji instead of a real photo.
struct EditTileCard: View {
    let tile: Tile
    /// For folder tiles: opens the folder's board in the editor.
    var onOpenFolder: (() -> Void)? = nil
    /// For folder tiles: a tile dropped on the "Open" chip moves inside the folder.
    var onDropIntoFolder: ((UUID) -> Bool)? = nil
    @State private var dropTargeted = false

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
                Image(systemName: "pencil")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.ink.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .background(.background.opacity(0.6), in: .circle)
                    .padding(8)
            }
            .overlay(alignment: .top) {
                // Top edge, between the badges and the pencil, so it never covers the label.
                if let onOpenFolder {
                    Button(action: onOpenFolder) {
                        Label(dropTargeted ? "Put inside" : "Open", systemImage: "folder.fill")
                            .labelStyle(OpenFolderLabelStyle(compact: geo.size.width < 150 && !dropTargeted))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(dropTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.35)) : AnyShapeStyle(.background.opacity(0.75)), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .dropDestination(for: String.self) { items, _ in
                        guard let id = items.first.flatMap(UUID.init(uuidString:)), let onDropIntoFolder else { return false }
                        return onDropIntoFolder(id)
                    } isTargeted: { dropTargeted = $0 && onDropIntoFolder != nil }
                    .help("Open the folder. Drop a tile here to put it inside.")
                    .padding(.top, 8)
                    .accessibilityLabel("Open folder")
                }
            }
        }
        .contentShape(.rect(cornerRadius: Theme.tileCorner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.label). Says: \(tile.spokenText)\(tile.isHidden ? ". Hidden" : "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("editTile.\(tile.label)")
        .accessibilityActions {
            if let onOpenFolder { Button("Open folder", action: onOpenFolder) }
        }
    }
}

/// Always-visible reminder that this is the grown-up editing view, with Back (inside a folder) and
/// the grid-size control.
private struct EditBand: View {
    let board: Board
    let parentName: String?
    let onBack: () -> Void
    let onGridSize: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let parentName {
                Button(action: onBack) {
                    Label(parentName, systemImage: "chevron.backward")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Back to \(parentName)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Editing \(board.name)")
                    .font(.system(.title3, design: .serif, weight: .semibold))
                Text("Tap a tile to change it, or an empty spot to add one. Drag to move; drop a tile on a folder's Open button to put it inside. Your child sees changes when you tap Done.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onGridSize) {
                HStack(spacing: 8) {
                    GridPreview(rows: board.rows, columns: board.columns).frame(width: 22, height: 22)
                    Text("\(board.rows) × \(board.columns)").monospacedDigit()
                }
                .font(.callout.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Grid size: \(board.rows) rows, \(board.columns) columns. Change")
            .accessibilityIdentifier("gridSize")
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

/// Icon and title on roomy tiles, icon only on narrow ones (iPhone).
private struct OpenFolderLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            if !compact { configuration.title }
        }
    }
}
