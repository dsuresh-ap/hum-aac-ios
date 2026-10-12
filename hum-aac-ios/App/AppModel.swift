// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import AVFoundation
import Observation
import SwiftData
import CoreData
import HumConfig
import CoreGraphics
import ImageIO
#if os(iOS)
import UIKit
#endif

/// What the child grid draws: a frozen copy of one board.
///
/// Child mode renders from this snapshot, never straight from SwiftData. Incoming changes (sync,
/// imports, App Intents) can then wait until the child is not mid-tap, and a slow fetch never
/// delays a tap.
struct BoardSnapshot: Equatable {
    struct Cell: Equatable, Identifiable {
        var id: UUID
        var label: String
        var spokenText: String
        var function: TileFunction?
        var colorHex: String?
        var symbol: String?
        var image: CGImage?
        var linkedBoardID: UUID?
        var linkedBoardExists: Bool
        /// Key of the decoded recording, if the parent recorded this phrase. Changes when re-recorded.
        var recordingKey: String?
        /// Set on the phone layout's "More" cell: tapping it opens this page of the same board.
        var nextPage: Int? = nil

        static func == (a: Cell, b: Cell) -> Bool {
            a.id == b.id && a.label == b.label && a.spokenText == b.spokenText && a.function == b.function
                && a.colorHex == b.colorHex && a.symbol == b.symbol && a.image === b.image
                && a.linkedBoardID == b.linkedBoardID && a.linkedBoardExists == b.linkedBoardExists
                && a.recordingKey == b.recordingKey && a.nextPage == b.nextPage
        }
    }

    var boardID: UUID
    var name: String
    var rows: Int
    var columns: Int
    var isHome: Bool
    /// `cells[row][column]`: nil is an empty or hidden slot. Hidden tiles keep their slot.
    var cells: [[Cell?]]
    /// The phone layout's page (0 on bigger screens).
    var page = 0
}

@MainActor
@Observable
final class AppModel {
    enum Mode: Equatable { case child, parent }

    private(set) var container: ModelContainer
    var context: ModelContext { container.mainContext }
    let settings: DeviceSettings
    let speech: SpeechService
    let history: SpeechHistory
    /// iCloud sync status for the parent (Setup & sharing).
    let sync = SyncMonitor()

    private(set) var snapshot: BoardSnapshot?
    private(set) var currentBoardID: UUID?
    var mode: Mode = .child {
        didSet {
            if mode == .parent {
                editPath = []
                editingBoardID = currentBoardID
                editingPage = currentPage
                showNextPendingChange()
            } else if oldValue == .parent {
                // Leaving parent mode: show the latest edits right away (the child isn't tapping yet).
                rebuildSnapshot()
            }
        }
    }
    /// The board shown in the parent editor.
    var editingBoardID: UUID?
    /// Folders opened while editing, so "Back" returns to the board you came from.
    var editPath: [UUID] = []
    /// The phone layout page shown in the editor (iPhone, big boards).
    var editingPage = 0

    /// Jumps the editor to a board (from a menu or the board list). Forgets the folder path.
    func editBoard(_ id: UUID?) {
        editPath = []
        editingBoardID = id
        editingPage = 0
    }

    /// Opens a folder in the editor, remembering where we came from.
    func openFolderInEditor(_ id: UUID) {
        guard id != editingBoardID else { return }
        if let current = editingBoardID ?? homeBoardID { editPath.append(current) }
        editingBoardID = id
        editingPage = 0
    }

    func backInEditor() {
        editingBoardID = editPath.popLast()
        editingPage = 0
    }

    // MARK: Phone layout

    /// True on iPhone: boards too big for a phone screen are shown in their phone layout (`PhoneLayout`).
    var usesPhoneLayout = AppModel.isPhone

    static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// Whether this device shows `board` in its phone layout instead of its own grid.
    func showsPhoneLayout(_ board: Board) -> Bool { usesPhoneLayout && !PhoneLayout.fits(board) }

    /// Gives new tiles a phone spot before the phone shows `board`. Not an undo step.
    func arrangePhoneLayout(_ board: Board) {
        guard showsPhoneLayout(board) else { return }
        store.withoutUndo { _ = PhoneLayout.arrange(board) }
    }
    /// True until a parent finishes first-run setup.
    var needsFirstRun: Bool
    @ObservationIgnored private(set) lazy var store = BoardStore(context: context)
    @ObservationIgnored private var remoteChangeObserver: NSObjectProtocol?

    // MARK: iCloud sync

    /// Turns iCloud sync on or off (parent action). Re-opens the same store with or without CloudKit.
    func setICloudSync(_ on: Bool) {
        settings.iCloudSyncEnabled = on
        // The old store's undo steps can't apply to the new one. Detach them first, and keep the old
        // container alive: freeing it while its undo manager has an open run-loop group crashes SwiftData.
        store.clearUndo()
        retiredContainers.append(container)
        container = Persistence.makeContainer(iCloud: on)
        store = BoardStore(context: container.mainContext)
        observeRemoteChanges()
        if on { SyncResolver.resolve(in: context) }
        editBoard(nil)
        goHome()
    }

    @ObservationIgnored private var retiredContainers: [ModelContainer] = []

    var iCloudActive: Bool { Persistence.activeMode == .iCloud }

    /// When another device's changes arrive: repair conflicts (never moving tiles), then refresh the
    /// child's board only once they haven't touched it for a moment.
    func observeRemoteChanges() {
        if let remoteChangeObserver { NotificationCenter.default.removeObserver(remoteChangeObserver) }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                SyncResolver.resolve(in: self.context)
                self.scheduleSnapshotRefresh()
            }
        }
    }

    /// An import waiting for the parent's preview (Merge / Replace everything).
    var pendingImport: PendingImport? {
        didSet {
            // The parent decided (applied or cancelled) on a queued change: drop it, show the next one.
            if pendingImport == nil, let done = oldValue?.queueFile {
                PendingChanges.remove(done)
                showNextPendingChange()
            }
        }
    }

    /// Changes queued by Shortcuts/Siri surface one at a time, only in parent mode.
    func showNextPendingChange() {
        guard mode == .parent, pendingImport == nil else { return }
        for url in PendingChanges.all() {
            do {
                var pending = try ImportService(model: self).prepare(url: url)
                pending = PendingImport(fileName: PendingChanges.displayName(url), loaded: pending.loaded,
                                        merge: pending.merge, replace: pending.replace, queueFile: url)
                pendingImport = pending
                return
            } catch {
                PendingChanges.remove(url)  // a broken queued file must not block the others
            }
        }
    }
    var importError: String?
    /// The import that just finished, for the editor's banner (cleared when the parent closes it).
    var lastImport: ImportReport?
    /// True while a sheet (Setup & sharing) shows the import preview itself; the root view waits.
    var importHostedBySheet = false
    /// True while stored SVG pictures are being turned into JPEGs.
    @ObservationIgnored var isConvertingSVGs = false

    /// Every way a file arrives (Files, AirDrop, "Open in Hum", drag and drop) ends here. Nothing
    /// changes until the parent sees the preview, and the preview only shows in parent mode.
    func requestImport(url: URL) {
        do {
            pendingImport = try ImportService(model: self).prepare(url: url)
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Last time the child touched a tile. Snapshot refreshes from outside wait for a quiet moment.
    @ObservationIgnored private var lastTouch = Date.distantPast
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    /// Decoded images, keyed by tile ID + byte count, so redraws don't decode again.
    @ObservationIgnored private var imageCache: [String: CGImage] = [:]
    #if os(iOS)
    @ObservationIgnored private let haptic = UIImpactFeedbackGenerator(style: .light)
    #endif

    init(container: ModelContainer, settings: DeviceSettings = DeviceSettings(), history: SpeechHistory = SpeechHistory()) {
        self.container = container
        self.settings = settings
        self.history = history
        self.speech = SpeechService(voice: nil)
        self.needsFirstRun = !settings.hasCompletedSetup
        applySpeechSettings()
    }

    // MARK: Launch

    func launch() {
        speech.start()
        observeRemoteChanges()
        observeVoiceChanges()
        upgradeVoiceIfBetterInstalled()
        if !needsFirstRun, ((try? context.fetchCount(FetchDescriptor<Board>())) ?? 0) == 0 {
            // Every board was deleted outside first run: never leave the child with nothing.
            try? loadStarterBoard()
        }
        goHome()
        // Pictures saved as SVG (older builds, or synced from another device) become JPEGs.
        Task { await ImportService.renderImportedSVGs(self) }
    }

    /// Finishes first-run setup with the parent's choice.
    enum StartChoice { case starter, empty(rows: Int, columns: Int) }

    func finishFirstRun(_ choice: StartChoice) {
        switch choice {
        case .starter:
            try? loadStarterBoard()
        case .empty(let rows, let columns):
            if ((try? context.fetchCount(FetchDescriptor<Board>())) ?? 0) == 0 {
                store.createBoard(name: "Home", rows: rows, columns: columns)
            }
        }
        settings.hasCompletedSetup = true
        needsFirstRun = false
        store.clearUndo()
        goHome()
    }

    /// Setup started with "Import a setup" and the import finished: setup is done. The file's own Home
    /// is Home, because nothing was made before it.
    func finishFirstRunAfterImport() {
        settings.hasCompletedSetup = true
        needsFirstRun = false
        store.clearUndo()
        lastImport = nil
        goHome()
    }

    /// The starter board ships as `starter.hum.json` and loads through the normal import path.
    func loadStarterBoard() throws {
        guard let url = Bundle.main.url(forResource: "starter.hum", withExtension: "json") else { return }
        let loaded = try HumConfigLoader.load(try Data(contentsOf: url))
        let existing = ConfigBridge.export(boards: store.boards()).document
        let plan = MergePlanner.plan(existing: existing, incoming: loaded.document, mode: .merge)
        try ConfigBridge.apply(plan, media: loaded.media, in: context)
        if let s = loaded.document.settings { settings.apply(s) }
        applySpeechSettings()
    }

    @ObservationIgnored private var voicesObserver: NSObjectProtocol?

    /// When a parent downloads a better voice in system Settings, use it right away.
    private func observeVoiceChanges() {
        voicesObserver = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.upgradeVoiceIfBetterInstalled() }
        }
    }

    /// "Device default" follows the best installed voice; a chosen voice moves to its Premium/Enhanced
    /// version of the same name when one appears. Clips are re-rendered for the new voice.
    func upgradeVoiceIfBetterInstalled() {
        if let chosen = settings.voiceIdentifier, let better = VoiceCatalog.upgrade(for: chosen) {
            settings.voiceIdentifier = better.identifier
        }
        let before = speech.voice
        applySpeechSettings()
        if speech.voice != before { rebuildSnapshot() }
    }

    func applySpeechSettings() {
        speech.update(voice: .init(
            identifier: settings.voiceIdentifier ?? SpeechService.defaultVoiceIdentifier(),
            rate: settings.rate, pitch: settings.pitch, volume: settings.volume))
        switch settings.retrigger {
        case .restart: speech.retrigger = .restart
        case .finish: speech.retrigger = .finish
        case .overlap: speech.retrigger = .overlap
        }
    }

    // MARK: Navigation

    /// Where the child has been: a board, and its phone layout page.
    struct Stop: Equatable {
        var board: UUID
        var page: Int
    }

    /// Boards (and phone pages) the child opened on the way to the current one, for the Back button.
    /// Home clears it.
    private(set) var boardPath: [Stop] = []
    /// The phone layout page being shown (always 0 on bigger screens).
    private(set) var currentPage = 0
    var canGoBack: Bool { !boardPath.isEmpty }

    var homeBoardID: UUID? {
        let boards = (try? context.fetch(FetchDescriptor<Board>())) ?? []
        return (boards.first(where: \.isHome) ?? boards.sorted { $0.createdAt < $1.createdAt }.first)?.id
    }

    func goHome() {
        boardPath = []
        show(boardID: homeBoardID)
    }

    /// Opens a folder's board, remembering where we came from.
    func open(boardID: UUID) {
        guard boardID != currentBoardID else { return }
        if let current = currentBoardID {
            // Opening a board that is already on the path (a loop of links) goes back to it instead
            // of growing the path forever.
            if let index = boardPath.firstIndex(where: { $0.board == boardID }) {
                boardPath.removeSubrange(index...)
            } else {
                boardPath.append(Stop(board: current, page: currentPage))
            }
        }
        if boardID == homeBoardID { boardPath = [] }
        show(boardID: boardID)
    }

    /// Opens another page of the current board's phone layout ("More"). Back returns to this page.
    func openPage(_ page: Int) {
        guard let current = currentBoardID, page != currentPage else { return }
        boardPath.append(Stop(board: current, page: currentPage))
        show(boardID: current, page: page)
    }

    func goBack() {
        guard let previous = boardPath.popLast() else { return goHome() }
        show(boardID: previous.board, page: previous.page)
    }

    func show(boardID: UUID?, page: Int = 0) {
        currentBoardID = boardID
        currentPage = page
        rebuildSnapshot()
    }

    // MARK: Taps

    /// Called from the touch handler. Sound first, everything else after.
    func tap(_ cell: BoardSnapshot.Cell, tapTime: UInt64) {
        lastTouch = .now
        if let page = cell.nextPage { return openPage(page) }
        // A silent folder tile (no phrase, no recording) just opens its board.
        if !cell.spokenText.isEmpty || cell.recordingKey != nil {
            speech.speak(cell.spokenText, recordingID: cell.recordingKey, tapTime: tapTime)
            history.add(label: cell.label, spokenText: cell.spokenText, function: cell.function, colorHex: cell.colorHex)
            if settings.sentenceStrip { strip.append(cell) }
        }
        #if os(iOS)
        if settings.haptics { haptic.impactOccurred(intensity: 0.5) }
        #endif
        if let link = cell.linkedBoardID, cell.linkedBoardExists {
            open(boardID: link)
        } else if settings.returnHomeAfterFolderTap, canGoBack {
            goHome()
        }
    }

    func noteTouch() { lastTouch = .now }

    // MARK: Snapshots

    /// Rebuilds the snapshot now (navigation, leaving parent mode).
    func rebuildSnapshot() {
        guard let id = currentBoardID,
              let board = fetchBoard(id) else {
            // The board was deleted (e.g. "Replace everything" on another device): go Home instead of
            // leaving the child with an empty screen.
            if let home = homeBoardID, home != currentBoardID, fetchBoard(home) != nil {
                boardPath = []
                show(boardID: home)
            } else {
                snapshot = nil
            }
            return
        }
        let allBoardIDs = Set(((try? context.fetch(FetchDescriptor<Board>())) ?? []).map(\.id))
        let phone = showsPhoneLayout(board)
        if phone { arrangePhoneLayout(board) }
        let pageCount = phone ? PhoneLayout.pageCount(board) : 1
        let page = min(currentPage, pageCount - 1)
        let (rows, columns) = phone ? (PhoneLayout.rows, PhoneLayout.columns) : (board.rows, board.columns)
        var cells = [[BoardSnapshot.Cell?]](repeating: [BoardSnapshot.Cell?](repeating: nil, count: columns), count: rows)
        var recordings: [(id: String, data: Data)] = []
        for tile in board.placedTiles where !tile.isHidden {
            let spot: (Int, Int)?
            if phone {
                spot = PhoneLayout.spot(of: tile).flatMap { $0.page == page ? ($0.row, $0.column) : nil }
            } else {
                spot = tile.row.flatMap { r in tile.column.map { (r, $0) } }
            }
            guard let (r, c) = spot, r < rows, c < columns, cells[r][c] == nil else { continue }
            let key = tile.audioData.map { Self.recordingKey(tile.id, $0) }
            if let key, let audio = tile.audioData { recordings.append((key, audio)) }
            cells[r][c] = BoardSnapshot.Cell(
                id: tile.id, label: tile.label, spokenText: tile.spokenText, function: tile.function,
                colorHex: tile.colorHex, symbol: tile.symbol, image: image(for: tile),
                linkedBoardID: tile.linkedBoardID,
                linkedBoardExists: tile.linkedBoardID.map(allBoardIDs.contains) ?? false,
                recordingKey: key)
        }
        if phone, page < pageCount - 1 {
            cells[PhoneLayout.rows - 1][PhoneLayout.columns - 1] = BoardSnapshot.Cell(
                id: Self.moreCellID(board.id, page: page), label: "More", spokenText: "", function: nil, colorHex: nil,
                symbol: "➡️", image: nil, linkedBoardID: nil, linkedBoardExists: false, recordingKey: nil, nextPage: page + 1)
        }
        snapshot = BoardSnapshot(boardID: board.id, name: board.name, rows: rows, columns: columns, isHome: board.isHome,
                                 cells: cells, page: page)
        speech.prepareRecordings(recordings)
        prerender(board)
    }

    /// For changes that arrive from outside (sync, App Intents): wait until the child has not touched
    /// the screen for 2 seconds, then refresh. Tiles never change under a finger.
    func scheduleSnapshotRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor in
            while Date.now.timeIntervalSince(lastTouch) < 2 {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
            }
            rebuildSnapshot()
        }
    }

    /// Current board first, then the boards one link away.
    private func prerender(_ board: Board) {
        let tiles = board.placedTiles.filter { !$0.isHidden }
        speech.prepare(tiles.map(\.spokenText))
        for linkID in Set(tiles.compactMap(\.linkedBoardID)) {
            if let linked = fetchBoard(linkID) {
                speech.prepare(linked.placedTiles.filter { !$0.isHidden }.map(\.spokenText))
            }
        }
    }

    func fetchBoard(_ id: UUID) -> Board? {
        var descriptor = FetchDescriptor<Board>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// A stable ID for a board page's "More" cell, so SwiftUI keeps the same view between rebuilds.
    static func moreCellID(_ board: UUID, page: Int) -> UUID {
        var bytes = board.uuid
        bytes.15 ^= UInt8(truncatingIfNeeded: page + 1)
        bytes.14 ^= 0x5A
        return UUID(uuid: bytes)
    }

    /// Tile ID + size + a cheap content hash, so a new recording never plays the old one.
    static func recordingKey(_ id: UUID, _ data: Data) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in data.prefix(4096) { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return "\(id.uuidString)-\(data.count)-\(hash)"
    }

    // MARK: Sentence strip (off by default; for NLA Stage 3+)

    /// Tiles tapped while the strip is on. Each tile still speaks on its own when tapped.
    var strip: [BoardSnapshot.Cell] = []

    func speakStrip() {
        guard !strip.isEmpty else { return }
        lastTouch = .now
        speech.speak(strip.map(\.spokenText).filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// Says a history entry again (tapping it in the history box).
    func replay(_ entry: SpeechHistory.Entry) {
        lastTouch = .now
        speech.speak(entry.spokenText)
    }

    func clearStrip() { strip.removeAll() }

    /// Decodes a tile photo at display size (≤ 512 px) once and caches it.
    private func image(for tile: Tile) -> CGImage? {
        guard let data = tile.imageData else { return nil }
        let key = "\(tile.id)-\(data.count)"
        if let cached = imageCache[key] { return cached }
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        var image = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
        #if os(macOS)
        // An SVG still waiting to be converted (see `ImportService.renderImportedSVGs`).
        if image == nil, ImageProcessing.isSVG(data) { image = ImageProcessing.rasterizeSVG(data) }
        #endif
        imageCache[key] = image
        return image
    }
}
