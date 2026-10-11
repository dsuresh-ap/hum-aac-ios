// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import SwiftData
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
        var hasRecording: Bool

        static func == (a: Cell, b: Cell) -> Bool {
            a.id == b.id && a.label == b.label && a.spokenText == b.spokenText && a.function == b.function
                && a.colorHex == b.colorHex && a.symbol == b.symbol && a.image === b.image
                && a.linkedBoardID == b.linkedBoardID && a.linkedBoardExists == b.linkedBoardExists
                && a.hasRecording == b.hasRecording
        }
    }

    var boardID: UUID
    var name: String
    var rows: Int
    var columns: Int
    var isHome: Bool
    /// `cells[row][column]`: nil is an empty or hidden slot. Hidden tiles keep their slot.
    var cells: [[Cell?]]
}

@MainActor
@Observable
final class AppModel {
    enum Mode: Equatable { case child, parent }

    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let settings: DeviceSettings
    let speech: SpeechService

    private(set) var snapshot: BoardSnapshot?
    private(set) var currentBoardID: UUID?
    var mode: Mode = .child {
        didSet {
            if mode == .parent {
                editingBoardID = currentBoardID
            } else if oldValue == .parent {
                // Leaving parent mode: show the latest edits right away (the child isn't tapping yet).
                rebuildSnapshot()
            }
        }
    }
    /// The board shown in the parent editor.
    var editingBoardID: UUID?
    /// True until a parent finishes first-run setup.
    var needsFirstRun: Bool
    @ObservationIgnored private(set) lazy var store = BoardStore(context: context)

    /// An import waiting for the parent's preview (Merge / Replace everything).
    var pendingImport: PendingImport?
    var importError: String?

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

    init(container: ModelContainer, settings: DeviceSettings = DeviceSettings()) {
        self.container = container
        self.settings = settings
        self.speech = SpeechService(voice: nil)
        self.needsFirstRun = !settings.hasCompletedSetup
        applySpeechSettings()
    }

    // MARK: Launch

    func launch() {
        speech.start()
        if !needsFirstRun, ((try? context.fetchCount(FetchDescriptor<Board>())) ?? 0) == 0 {
            // Every board was deleted outside first run: never leave the child with nothing.
            try? loadStarterBoard()
        }
        goHome()
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

    func goHome() {
        let boards = (try? context.fetch(FetchDescriptor<Board>())) ?? []
        let home = boards.first(where: \.isHome) ?? boards.sorted { $0.createdAt < $1.createdAt }.first
        show(boardID: home?.id)
    }

    func show(boardID: UUID?) {
        currentBoardID = boardID
        rebuildSnapshot()
    }

    // MARK: Taps

    /// Called from the touch handler. Sound first, everything else after.
    func tap(_ cell: BoardSnapshot.Cell, tapTime: UInt64) {
        lastTouch = .now
        speech.speak(cell.spokenText, recordingID: cell.hasRecording ? recordingKey(cell.id) : nil, tapTime: tapTime)
        #if os(iOS)
        if settings.haptics { haptic.impactOccurred(intensity: 0.5) }
        #endif
        if let link = cell.linkedBoardID, cell.linkedBoardExists {
            show(boardID: link)
        }
    }

    func noteTouch() { lastTouch = .now }

    // MARK: Snapshots

    /// Rebuilds the snapshot now (navigation, leaving parent mode).
    func rebuildSnapshot() {
        guard let id = currentBoardID,
              let board = fetchBoard(id) else {
            snapshot = nil
            return
        }
        let allBoardIDs = Set(((try? context.fetch(FetchDescriptor<Board>())) ?? []).map(\.id))
        var cells = [[BoardSnapshot.Cell?]](repeating: [BoardSnapshot.Cell?](repeating: nil, count: board.columns), count: board.rows)
        var recordings: [(id: String, data: Data)] = []
        for tile in board.placedTiles where !tile.isHidden {
            guard let r = tile.row, let c = tile.column, r < board.rows, c < board.columns, cells[r][c] == nil else { continue }
            if let audio = tile.audioData { recordings.append((recordingKey(tile.id), audio)) }
            cells[r][c] = BoardSnapshot.Cell(
                id: tile.id, label: tile.label, spokenText: tile.spokenText, function: tile.function,
                colorHex: tile.colorHex, symbol: tile.symbol, image: image(for: tile),
                linkedBoardID: tile.linkedBoardID,
                linkedBoardExists: tile.linkedBoardID.map(allBoardIDs.contains) ?? false,
                hasRecording: tile.audioData != nil)
        }
        snapshot = BoardSnapshot(boardID: board.id, name: board.name, rows: board.rows, columns: board.columns, isHome: board.isHome, cells: cells)
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

    private func recordingKey(_ id: UUID) -> String { id.uuidString }

    /// Decodes a tile photo at display size (≤ 512 px) once and caches it.
    private func image(for tile: Tile) -> CGImage? {
        guard let data = tile.imageData else { return nil }
        let key = "\(tile.id)-\(data.count)"
        if let cached = imageCache[key] { return cached }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        imageCache[key] = image
        return image
    }
}
