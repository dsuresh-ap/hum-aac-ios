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
    @State private var showFinder = false
    @State private var errorMessage: String?
    @State private var notice: EditNotice?

    private var board: Board? {
        boards.first { $0.id == model.editingBoardID } ?? boards.first(where: \.isHome) ?? boards.first
    }

    private var anySheet: Bool {
        editor != nil || showBoards || showSettings || showSharing || showGridSize || showHistory || showAI || showPaste || showFinder
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
                        // Below the band, not over it.
                        if let report = model.lastImport {
                            ImportBanner(report: report,
                                         onOpen: { model.editBoard($0); model.lastImport = nil },
                                         onClose: { model.lastImport = nil })
                        }
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
            .navigationTitle(board?.name ?? String(localized: "Boards"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            // Page-sized on a big iPad, so the tile editor and the long forms aren't a small card in the
            // middle of the screen (BUGS.md, HUM-045). Same as before on iPhone and Mac.
            .sheet(item: $editor) { request in
                TileEditorSheet(request: request).modifier(PageSizedSheet())
            }
            .sheet(isPresented: $showBoards) { BoardManagerView().modifier(PageSizedSheet()) }
            .sheet(isPresented: $showSettings) { SettingsView().modifier(PageSizedSheet()) }
            .sheet(isPresented: $showSharing) { SetupSharingView().modifier(PageSizedSheet()) }
            .sheet(isPresented: $showGridSize) { if let board { GridSizeSheet(board: board) } }
            .sheet(isPresented: $showHistory) { HistoryView() }
            .sheet(isPresented: $showAI) { AIHelperView() }
            .sheet(isPresented: $showPaste) { PastePhrasesSheet() }
            .sheet(isPresented: $showFinder) { WordFinderView(purpose: .editor) { model.showInEditor($0) } }
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
            .task {
                #if os(iOS)
                // After the switch from the child's grid has settled: an alert asked for during the
                // transition can be dropped, and then the one-time tip never shows (BUGS.md, HUM-041).
                try? await Task.sleep(for: .milliseconds(700))
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
            find: { showFinder = true },
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
            errorMessage = String(localized: "\(board.name) is full. Make the tiles smaller (the size button at the top right) or hide a tile you don't need.")
            return
        }
        editor = TileEditorRequest(kind: .new(boardID: board.id, row: spot.row, column: spot.column), startsAsFolder: folder,
                                   phoneSpot: model.showsPhoneLayout(board) ? PhoneLayout.firstFreeSpot(on: board) : nil)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            // The word, not a bare checkmark: it's how a parent gets back to their child's board.
            Button("Done") { model.mode = .child }
                .accessibilityIdentifier("exitParentMode")
        }
        #if os(iOS)
        // Next to Done, so it never hides in the toolbar's "⋯" menu on iPhone.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("settings")
        }
        #endif
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
                    // Home first, then A→Z: a big import can add a hundred folders.
                    ForEach(boards.sorted { ($0.isHome ? 0 : 1, $0.name.lowercased()) < ($1.isHome ? 0 : 1, $1.name.lowercased()) }) { b in
                        Label(b.name, systemImage: b.isHome ? "house" : "folder").tag(Optional(b.id))
                    }
                }
                Divider()
                Button("Home & folders…", systemImage: "rectangle.stack") { showBoards = true }
            } label: {
                Label("Home & folders", systemImage: "rectangle.stack")
            }
            .help("Go to another board, or manage Home and folders")
            .accessibilityIdentifier("boardsMenu")

            Button {
                showFinder = true
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .help("Find a tile or folder")
            .accessibilityIdentifier("findTile")

            Button {
                model.store.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!(model.store.undoManager?.canUndo ?? false))
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo the last change")

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
            .help("What your child said recently")
            .accessibilityIdentifier("history")

            Button {
                showSharing = true
            } label: {
                Label("Share & sync", systemImage: "square.and.arrow.up.on.square")
            }
            .help("Copy your boards to another device, or keep your devices in sync")
            .accessibilityIdentifier("setupSharing")

            #if os(macOS)
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Voice, tiles and the grown-up lock")
            .accessibilityIdentifier("settings")
            #endif
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
    /// Added from an iPhone's phone layout: the phone spot that was tapped.
    var phoneSpot: PhoneLayout.Spot? = nil
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
    /// The smallest an edit tile gets (points). Below this the editor scrolls.
    static let minimumTile: CGFloat = 72

    /// The tile whose "Delete tile" was chosen from the long-press menu, waiting for the parent to confirm.
    @State private var confirmDelete: Tile?

    /// True on iPhone for boards too big for its screen: the editor shows and edits the phone layout.
    private var phone: Bool { model.showsPhoneLayout(board) }
    /// The board's rows plus a spare empty row to add tiles in (`BoardStore.editorRows`).
    private var rows: Int { phone ? PhoneLayout.rows : BoardStore.editorRows(board) }
    private var columns: Int { phone ? PhoneLayout.columns : board.columns }
    /// The phone pages, plus an empty one after them when the parent turned to it to add tiles there.
    private var pageCount: Int { max(PhoneLayout.pageCount(board), model.editingPage + 1) }
    private var page: Int { phone ? min(model.editingPage, pageCount - 1) : 0 }

    var body: some View {
        VStack(spacing: 8) {
            if phone { pageBar }
            GeometryReader { geo in
                let spacing = phone ? 8 : Theme.gridSpacing
                // Edit tiles never get smaller than this. When the board doesn't fit, the editor scrolls
                // instead of squeezing tiles on top of each other (iPhone in landscape, tall boards).
                // Off the phone layout, tiles get the same shape as on the child's board, which scrolls too.
                let fitWidth = GridMetrics.tileWidth(across: geo.size.width, columns: columns, spacing: spacing)
                let fitHeight = phone
                    ? (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
                    : GridMetrics.layout(in: geo.size, rows: board.rows, columns: columns, spacing: spacing).tileHeight
                let width = max(fitWidth, Self.minimumTile)
                let height = max(fitHeight, Self.minimumTile)
                let tallerThanScreen = height * CGFloat(rows) + spacing * CGFloat(rows - 1) > geo.size.height + 0.5
                let axes: Axis.Set = [fitWidth < Self.minimumTile ? .horizontal : [], tallerThanScreen ? .vertical : []]
                let byPosition: [String: Tile] = phone
                    ? Dictionary(uniqueKeysWithValues: PhoneLayout.tiles(on: board, page: page).map { ("\($0.key.row),\($0.key.column)", $0.value) })
                    : Dictionary(board.placedTiles.map { ("\($0.row!),\($0.column!)", $0) }, uniquingKeysWith: { a, _ in a })
                let grid = VStack(spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<columns, id: \.self) { column in
                                Group {
                                    if phone && PhoneLayout.isMoreSpot(row: row, column: column) {
                                        moreSlot
                                    } else {
                                        slot(tile: byPosition["\(row),\(column)"], row: row, column: column,
                                             roomy: height >= 120 && width >= 120)
                                    }
                                }
                                .frame(width: width, height: height)
                                .id(byPosition["\(row),\(column)"]?.id)
                            }
                        }
                    }
                }
                .overlay(alignment: .top) {
                    // Where the child's screen ends, so the parent can keep important tiles above it.
                    if let fold = childFold, fold < rows {
                        FoldLine().offset(y: CGFloat(fold) * (height + spacing) - spacing / 2 - 1)
                    }
                }
                if axes.isEmpty {
                    grid
                } else {
                    // Dragging a tile near an edge scrolls, so far spots can still be reached.
                    ScrollViewReader { proxy in
                        ScrollView(axes) { grid }
                            .scrollIndicators(.visible)
                            .accessibilityIdentifier("editGridScroll")
                            // A tile found with Find may be off screen.
                            .task(id: model.editorHighlightID) {
                                if let id = model.editorHighlightID { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                            }
                    }
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.editorBoardArea = $0 }
        // New tiles (added on a Mac, or from an import) get a phone spot before they're shown here.
        .task(id: "\(board.id)-\(board.placedTiles.count)") { model.arrangePhoneLayout(board) }
        // Every delete asks first, like the tile editor's.
        .confirmationDialog("Delete this tile?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { tile in
            Button("Delete tile", role: .destructive) { model.store.delete(tile) }
        } message: { _ in
            Text("Its spot will be empty. Other tiles stay where they are. You can undo this.")
        }
    }

    /// How many rows the child sees before scrolling, or nil when the whole board shows (or isn't known yet).
    private var childFold: Int? {
        guard !phone, model.boardArea != .zero else { return nil }
        let visible = GridMetrics.visibleRows(in: model.boardArea, rows: board.rows, columns: columns, spacing: Theme.gridSpacing)
        return visible < rows ? visible : nil
    }

    /// "Page 1 of 2" with arrows, for boards shown in their phone layout.
    private var pageBar: some View {
        HStack {
            Button { model.editingPage = page - 1 } label: { Image(systemName: "chevron.left") }
                .disabled(page == 0)
                .accessibilityLabel("Previous page")
                .help("Previous page")
            Spacer()
            Text("Page \(page + 1) of \(pageCount)")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityIdentifier("phonePage")
            Spacer()
            Button { model.editingPage = page + 1 } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(page + 1 < pageCount ? "Next page" : "New page")
                .help(page + 1 < pageCount ? "Next page" : "New page")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// The bottom-right spot of a phone page: "More" opens the next page (for the child too).
    private var moreSlot: some View {
        Button { model.editingPage = page + 1 } label: {
            RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                .fill(Theme.ink.opacity(0.06))
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                        Text(page + 1 < PhoneLayout.pageCount(board) ? "More" : "New page").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.ink.opacity(0.55))
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("phoneMore")
    }

    /// Folders a tile could move into: every board except this one and the folder the tile itself opens.
    private func destinations(for tile: Tile) -> [Board] {
        boards.filter { $0.id != board.id && $0.id != tile.linkedBoardID }
    }

    private func moveIntoFolder(_ tile: Tile, _ folder: Board) {
        let placed = model.store.moveToBoard(tile, folder)
        withAnimation {
            notice = EditNotice(
                text: placed ? String(localized: "Moved “\(tile.label)” into \(folder.name).")
                    : String(localized: "Moved “\(tile.label)” into \(folder.name). That folder is full, so the tile waits below it for a spot."),
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
                    .overlay { if model.editorHighlightID == tile.id { FinderGlow() } }
                    .task(id: model.editorHighlightID) {
                        // The ring fades after a few seconds.
                        guard model.editorHighlightID == tile.id else { return }
                        try? await Task.sleep(for: .seconds(4))
                        if model.editorHighlightID == tile.id { model.editorHighlightID = nil }
                    }
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
                                    Button(folder.isHome ? String(localized: "\(folder.name) (Home)") : folder.name) { moveIntoFolder(tile, folder) }
                                }
                            }
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            if model.store.duplicate(tile)?.row == nil {
                                errorMessage = String(localized: "\(board.name) is full. The new copy is waiting below the board for a spot.")
                            }
                        }
                        Button(tile.isHidden ? "Show tile" : "Hide tile", systemImage: tile.isHidden ? "eye" : "eye.slash") {
                            model.store.setHidden(tile, !tile.isHidden)
                        }
                        Divider()
                        Button("Delete tile", systemImage: "trash", role: .destructive) { confirmDelete = tile }
                    }
                    .accessibilityHint("Opens the tile so you can change it. You can also drag it to a new spot.")
            } else {
                EmptySlot(row: row, column: column, roomy: roomy, add: { folder in add(row: row, column: column, folder: folder) })
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)),
                  let dragged = (board.tiles ?? []).first(where: { $0.id == id }) else { return false }
            if phone {
                // Only the phone layout changes; iPad and Mac keep their spots.
                if !model.store.movePhone(dragged, to: PhoneLayout.Spot(page: page, row: row, column: column), on: board) {
                    errorMessage = String(localized: "\(board.name) is full on iPad and Mac. Make its tiles smaller there first.")
                }
            } else {
                model.store.move(dragged, to: row, column: column, on: board)
            }
            return true
        }
    }

    /// A new tile or folder in this spot. On the phone layout it also needs a spot on the board's own grid
    /// (iPad and Mac): the first empty one.
    private func add(row: Int, column: Int, folder: Bool) {
        guard phone else {
            editor = TileEditorRequest(kind: .new(boardID: board.id, row: row, column: column), startsAsFolder: folder)
            return
        }
        guard let bigSpot = model.store.firstEmptySpot(on: board) else {
            errorMessage = String(localized: "\(board.name) is full on iPad and Mac. Make its tiles smaller there first.")
            return
        }
        editor = TileEditorRequest(kind: .new(boardID: board.id, row: bigSpot.row, column: bigSpot.column), startsAsFolder: folder,
                                   phoneSpot: PhoneLayout.Spot(page: page, row: row, column: column))
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

    private var ink: Color { Theme.tileInk(function: tile.function, hex: tile.colorHex) }

    /// What VoiceOver reads for the tile in edit mode.
    private var accessibilityText: String {
        if tile.modelContext == nil || tile.isDeleted { return "" }
        return tile.isHidden ? String(localized: "\(tile.label). Says: \(tile.spokenText). Hidden")
            : String(localized: "\(tile.label). Says: \(tile.spokenText)")
    }

    var body: some View {
        // A tile deleted by an import or a synced change can be drawn once more before its board
        // updates; reading its picture then would crash SwiftData.
        if tile.modelContext == nil || tile.isDeleted {
            Color.clear
        } else {
            card
        }
    }

    private var card: some View {
        GeometryReader { geo in
            // Checked again here: this runs later than `body`, and Undo of a big import can delete the
            // tile in between (BUGS.md, HUM-038).
            if tile.modelContext == nil || tile.isDeleted {
                Color.clear
            } else {
                cardFace(geo)
            }
        }
        .contentShape(.rect(cornerRadius: Theme.tileCorner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(tile.modelContext == nil || tile.isDeleted ? "" : "editTile.\(tile.label)")
        .accessibilityActions {
            if let onOpenFolder { Button("Open folder", action: onOpenFolder) }
        }
    }

    private func cardFace(_ geo: GeometryProxy) -> some View {
        Group {
            let size = min(geo.size.width, geo.size.height)
            // Narrow tiles (iPhone, big boards) keep their badges in a strip above the picture, so nothing
            // covers it, and the folder's Open button sits in a corner, so tapping the picture edits the
            // tile (BUGS.md, HUM-006 and HUM-007).
            let compact = geo.size.width < 150 || geo.size.height < 120
            // Wide, short tiles (iPhone in landscape): picture beside the label, like the child sees it,
            // with the badges down the right-hand side.
            let wide = TileShape.isWide(geo.size)
            Group {
                if wide {
                    let side = max(geo.size.height - 12, 0)
                    HStack(spacing: 8) {
                        picture(fontSize: side * 0.7).frame(width: side, height: side)
                        TileLabel(text: tile.label, fontSize: max(13, geo.size.height * 0.24),
                                  width: geo.size.width - side - 60)
                            .foregroundStyle(ink)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.leading, 6).padding(.vertical, 6).padding(.trailing, 36)
                } else {
                    VStack(spacing: 4) {
                        picture(fontSize: size * (compact ? 0.3 : 0.36))
                        TileLabel(text: tile.label, fontSize: max(13, size * 0.11), width: geo.size.width - (compact ? 12 : 20))
                            .foregroundStyle(ink)
                    }
                    .padding(.horizontal, compact ? 6 : 10)
                    .padding(.bottom, compact ? 6 : 10)
                    .padding(.top, compact ? 30 : 10)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Theme.tileColor(function: tile.function, hex: tile.colorHex), in: .rect(cornerRadius: Theme.tileCorner, style: .continuous))
            .opacity(tile.isHidden ? 0.45 : 1)
            .overlay(alignment: wide ? .bottomTrailing : .topLeading) {
                HStack(spacing: 6) {
                    if compact || wide, let onOpenFolder { openButton(onOpenFolder, compact: true) }
                    if tile.isHidden { Image(systemName: "eye.slash") }
                    // The "no photo yet" reminder only where there's room for it.
                    if tile.imageData == nil && !compact { Image(systemName: "camera").accessibilityLabel("No photo yet") }
                    if tile.audioData != nil { Image(systemName: "waveform").accessibilityLabel("Has a recording") }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(ink.opacity(0.45))
                .padding(compact ? 4 : 10)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "pencil")
                    .font((compact ? Font.caption2 : .footnote).weight(.bold))
                    .foregroundStyle(Theme.ink.opacity(0.55))
                    .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
                    .background(.background.opacity(0.6), in: .circle)
                    .padding(compact ? 4 : 8)
            }
            .overlay(alignment: .top) {
                // Top edge, between the badges and the pencil, so it never covers the label.
                if !compact && !wide, let onOpenFolder {
                    openButton(onOpenFolder, compact: geo.size.width < 150 && !dropTargeted)
                        .padding(.top, 8)
                }
            }
        }
    }

    /// The tile's photo, or its emoji at `fontSize`. Fit, like child mode: never wider or taller than the tile.
    @ViewBuilder
    private func picture(fontSize: CGFloat) -> some View {
        if let data = tile.imageData, let image = PlatformImage.thumbnail(data) {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
                .clipShape(.rect(cornerRadius: Theme.tileCorner * 0.6, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text(tile.symbol ?? "")
                .font(.system(size: fontSize))
                .minimumScaleFactor(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// "Open" on a folder tile. A tile dropped on it moves inside the folder.
    private func openButton(_ action: @escaping () -> Void, compact: Bool) -> some View {
        Button(action: action) {
            Label(dropTargeted ? "Put inside" : "Open", systemImage: "folder.fill")
                .labelStyle(OpenFolderLabelStyle(compact: compact && !dropTargeted))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, compact ? 7 : 10).padding(.vertical, compact ? 4 : 6)
                .background(dropTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.35)) : AnyShapeStyle(.background.opacity(0.75)), in: .capsule)
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)), let onDropIntoFolder else { return false }
            return onDropIntoFolder(id)
        } isTargeted: { dropTargeted = $0 && onDropIntoFolder != nil }
        .help("Open the folder. Drop a tile here to put it inside.")
        .accessibilityLabel("Open folder")
    }
}

/// What a finished import did, at the top of the editor until the parent closes it: where the new
/// boards went, with a button to open them (BUGS.md, HUM-027 and HUM-047).
private struct ImportBanner: View {
    let report: ImportReport
    let onOpen: (UUID) -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(report.message).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let id = report.folderID {
                Button("Open") { onOpen(id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("openImported")
            }
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close this message")
                .help("Close this message")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12).padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importBanner")
    }
}

/// Always-visible reminder that this is the grown-up editing view, with Back (inside a folder) and
/// the grid-size control.
private struct EditBand: View {
    let board: Board
    let parentName: String?
    let onBack: () -> Void
    let onGridSize: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    /// iPhone (narrow) or an iPhone in landscape (short): one short line of help at most.
    private var tight: Bool {
        #if os(iOS)
        if verticalSizeClass == .compact { return true }
        #endif
        return sizeClass == .compact
    }

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
                    .lineLimit(1).minimumScaleFactor(0.7)
                // iPhone: one short line, so the grid keeps the room (BUGS.md, HUM-010).
                if tight {
                    if parentName == nil {
                        Text("Tap a tile to change it. Drag to move.")
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                } else {
                    Text("Tap a tile to change it. Tap an empty spot to add one. To move a tile, drag it. To put a tile inside a folder, drop it on the folder's Open button. Your child sees changes when you tap Done.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: onGridSize) {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                    Text("\(board.columns) across").monospacedDigit()
                }
                .font(.callout.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Tile size: \(board.columns) across")
            .accessibilityHint("Makes the tiles on this board bigger or smaller")
            .accessibilityIdentifier("gridSize")
        }
        .padding(.horizontal, Theme.gridPadding + 4)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.editBand)
    }
}

/// A dashed line across the editor where the child's screen ends; rows below it are reached by scrolling.
private struct FoldLine: View {
    var body: some View {
        ZStack(alignment: .trailing) {
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .frame(height: 2)
            Text("Scrolls below here")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Theme.editBand, in: .capsule)
                .offset(y: -12)
        }
        .foregroundStyle(Theme.ink.opacity(0.6))
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Your child scrolls to see the rows below here")
        .accessibilityIdentifier("scrollFold")
    }
}

/// New tiles that couldn't go where an import asked. The parent drags each one to a spot.
private struct UnplacedTray: View {
    let board: Board
    @Binding var editor: TileEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(board.unplacedTiles.count) tiles need a spot. Drag each one onto the board.")
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
        #if os(macOS)
        // An SVG still waiting to be converted (see `ImportService.renderImportedSVGs`).
        if ImageProcessing.isSVG(data) { return ImageProcessing.rasterizeSVG(data) }
        #endif
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

#if DEBUG
/// Edit-mode cards with a square picture (like Image Playground's): it must stay inside the tile.
#Preview("Edit cards fit pictures") {
    let picture: Data? = {
        let context = CGContext(data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        return context?.makeImage().flatMap { ImageProcessing.jpegData($0) }
    }()
    let folder = Tile(label: "Food", spokenText: "", row: 0, column: 0)
    folder.imageData = picture
    folder.linkedBoardID = UUID()
    let tile = Tile(label: "snack", spokenText: "Let's have a snack", row: 0, column: 1)
    tile.imageData = picture
    return HStack(spacing: 12) {
        EditTileCard(tile: folder, onOpenFolder: {}).frame(width: 260, height: 150)
        EditTileCard(tile: tile).frame(width: 130, height: 200)
    }
    .padding()
    .background(Theme.background)
}
#endif

/// A page-sized sheet where the system supports it (a big iPad); the default size elsewhere.
struct PageSizedSheet: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}
