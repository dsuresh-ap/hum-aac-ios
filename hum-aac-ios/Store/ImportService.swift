// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData
import UniformTypeIdentifiers
import HumConfig

extension UTType {
    /// A Hum setup package (zip with hum.json + media/). Declared in Hum-Info.plist.
    nonisolated static let humPackage = UTType(exportedAs: "com.dhananjaysuresh.hum-aac.hum", conformingTo: .zip)
}

/// What the last import did, for the editor's "where did it go" banner.
struct ImportReport: Equatable {
    var fileName: String
    var summary: MergePlanner.Summary
    var mode: MergePlanner.Mode
    /// The folder to open from the banner: the file's Home made into a folder, or a new folder.
    var folderID: UUID?
    var folderName: String?

    var message: String {
        let s = summary
        var text: String
        if mode == .replace {
            text = String(localized: "Your boards are now the ones from “\(fileName)”. Undo brings back the old ones.")
        } else if let home = s.homeFolderName {
            text = s.newBoards > 1
                ? String(localized: "Added “\(fileName)” as a folder called “\(home)” on Home, with \(s.newBoards - 1) more folders inside.")
                : String(localized: "Added “\(fileName)” as a folder called “\(home)” on Home.")
        } else if s.newBoards > 0, let folderName {
            text = String(localized: "Added \(s.newTiles) tiles and a new folder, “\(folderName)”.")
        } else {
            text = s.newTiles > 0 ? String(localized: "Added \(s.newTiles) tiles.") : String(localized: "Updated \(s.changedTiles) tiles.")
        }
        if s.unplacedTiles > 0 {
            text += " " + String(localized: "\(s.unplacedTiles) tiles wait below the board for a spot.")
        }
        return text
    }
}

/// A file that has been read and checked, waiting for the parent to choose Merge or Replace.
struct PendingImport: Identifiable {
    var id = UUID()
    var fileName: String
    let loaded: LoadedConfig
    let merge: MergePlanner.Plan
    let replace: MergePlanner.Plan
    /// Set when this came from the Shortcuts/Siri queue; the file is removed once the parent decides.
    var queueFile: URL? = nil
}

/// A file still being read and checked in the background, before its preview.
struct ImportCheck: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    /// Set when this came from the Shortcuts/Siri queue.
    var queueFile: URL? = nil
}

/// What the import sheet shows: "Checking…" while the file is read, then its preview. Both have the same
/// ID, so the sheet stays open from one to the other.
enum ImportStage: Identifiable {
    case checking(ImportCheck)
    case ready(PendingImport)

    var id: UUID {
        switch self {
        case .checking(let check): check.id
        case .ready(let pending): pending.id
        }
    }
}

/// Reads, previews and applies imports; writes exports and backups.
///
/// Every import (files, AirDrop, "Open in Hum", AI, App Intents) ends in `apply`, which goes through
/// the merge planner, so no import path can move or delete tiles behind the parent's back.
@MainActor
struct ImportService {
    let model: AppModel

    /// Reads a file and plans both options. Throws `HumConfigError` with friendly text.
    func prepare(url: URL) async throws -> PendingImport {
        try await prepare(fileName: url.lastPathComponent) { try Self.read(url) }
    }

    func prepare(data: Data, fileName: String) async throws -> PendingImport {
        try await prepare(fileName: fileName) { data }
    }

    /// A big file takes seconds to unzip and check, so reading, unzipping, checking and planning all run
    /// in the background. Only reading the current boards (SwiftData) uses the main actor. Cancelling the
    /// calling task stops it, and nothing has changed.
    func prepare(fileName: String, read: @escaping @Sendable () throws -> Data) async throws -> PendingImport {
        let loaded = try await Self.inBackground {
            let data = try read()
            try Task.checkCancellation()
            return try HumConfigLoader.load(data)
        }
        try Task.checkCancellation()
        let existing = ConfigBridge.export(boards: model.store.boards()).document
        let name = Self.folderName(for: fileName)
        let (merge, replace) = try await Self.inBackground {
            (MergePlanner.plan(existing: existing, incoming: loaded.document, mode: .merge, name: name),
             MergePlanner.plan(existing: existing, incoming: loaded.document, mode: .replace))
        }
        try Task.checkCancellation()
        return PendingImport(fileName: fileName, loaded: loaded, merge: merge, replace: replace)
    }

    /// Also used by the AI helper with documents it built (small, so planned right here).
    func prepare(loaded: LoadedConfig, fileName: String) -> PendingImport {
        let existing = ConfigBridge.export(boards: model.store.boards()).document
        let name = Self.folderName(for: fileName)
        return PendingImport(
            fileName: fileName, loaded: loaded,
            merge: MergePlanner.plan(existing: existing, incoming: loaded.document, mode: .merge, name: name),
            replace: MergePlanner.plan(existing: existing, incoming: loaded.document, mode: .replace))
    }

    /// A merged file's own Home becomes a folder named after the file ("Express2-v2.hum" → "Express2-v2").
    nonisolated static func folderName(for fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// Reads a file the parent chose; it may be outside Hum's own folders.
    nonisolated static func read(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { return try Data(contentsOf: url) } catch {
            throw HumConfigError.badPackage(.unreadable)
        }
    }

    /// Runs `work` on a background thread, never the main actor. Cancelling the caller cancels it too.
    nonisolated static func inBackground<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated) { try work() }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    /// Where a long import is, for the preview's progress bar.
    enum Progress: Equatable {
        case backingUp
        case pictures(done: Int, total: Int)
        case saving

        var fraction: Double? {
            if case .pictures(let done, let total) = self, total > 0 { return Double(done) / Double(total) }
            return nil
        }

        var message: String {
            switch self {
            case .backingUp: String(localized: "Saving a backup of your boards…")
            case .pictures(_, 0): String(localized: "Getting ready…")
            case .pictures(let done, let total): String(localized: "Preparing pictures… \(done) of \(total)")
            case .saving: String(localized: "Saving your boards…")
            }
        }
    }

    /// Like `apply(_:mode:)`, but pictures are prepared in the background with progress, so a big setup
    /// doesn't freeze the app.
    func apply(_ pending: PendingImport, mode: MergePlanner.Mode, progress: (Progress) -> Void) async throws {
        let plan = mode == .merge ? pending.merge : pending.replace
        if mode == .replace {
            progress(.backingUp)
            await Task.yield()
            try writeBackup()
        }
        let prepared = await ConfigBridge.preparePictures(for: plan, media: pending.loaded.media) { done, total in
            progress(.pictures(done: done, total: total))
        }
        progress(.saving)
        await Task.yield()  // let the label update before the (short) save on the main actor
        try apply(pending, mode: mode, prepared: prepared, backupWritten: true)
    }

    /// Applies the parent's choice as one undoable step. "Replace everything" saves a backup first.
    func apply(_ pending: PendingImport, mode: MergePlanner.Mode, prepared: [String: Data?] = [:],
               backupWritten: Bool = false) throws {
        let plan = mode == .merge ? pending.merge : pending.replace
        if mode == .replace && !backupWritten { try writeBackup() }
        let before = Set(model.store.boards().map(\.id))
        if mode == .replace {
            try replaceEverything(with: plan.result, media: pending.loaded.media, prepared: prepared,
                                  settings: pending.loaded.document.settings)
        } else {
            try applyMerge(plan, media: pending.loaded.media, prepared: prepared)
            if model.fetchBoard(model.currentBoardID ?? UUID()) == nil { model.goHome() } else { model.scheduleSnapshotRefresh() }
        }
        // The folder the banner opens: one that a new tile on an existing board opens.
        let linked = Set(plan.result.boards.filter { before.contains($0.id) }.flatMap(\.tiles)
            .filter { plan.newTileIDs.contains($0.id) }.compactMap(\.linkedBoardID)
            + plan.unplaced.compactMap(\.tile.linkedBoardID))
        let folder = mode == .merge ? plan.result.boards.first { !before.contains($0.id) && linked.contains($0.id) } : nil
        model.lastImport = ImportReport(fileName: pending.fileName, summary: plan.summary, mode: mode,
                                        folderID: folder?.id, folderName: folder?.name)
        // Importing from first-run setup: setup is done once the import is (cancelling keeps setup open).
        if model.needsFirstRun { model.finishFirstRunAfterImport() }
        Task { await Self.renderImportedSVGs(model) }
    }

    /// A merge as one undo step. Before iOS 27, SwiftData's own undo takes existing tiles off their board
    /// (BUGS.md, HUM-052), so Undo puts back what the merge touched and Redo merges again.
    private func applyMerge(_ plan: MergePlanner.Plan, media: [String: Data], prepared: [String: Data?]) throws {
        let incoming = plan.result.boards.flatMap(\.tiles) + plan.unplaced.map(\.tile)
        let model = self.model
        try model.store.change("Import", restoring: Set(incoming.map(\.id)), boards: Set(plan.result.boards.map(\.id)),
                               mediaOf: Set(incoming.filter { $0.image != nil || $0.audio != nil }.map(\.id)),
                               redo: { _ in try? ImportService(model: model).applyMerge(plan, media: media, prepared: prepared) }) {
            try ConfigBridge.apply(plan, media: media, prepared: prepared, in: model.context)
        }
    }

    /// "Replace everything" as one undo step. SwiftData can't undo deleting a whole setup (the tiles come
    /// back without their boards, BUGS.md HUM-038), so Undo puts the setup from just before back the same
    /// way, and Redo replaces it again.
    private func replaceEverything(with document: HumDocument, media: [String: Data], prepared: [String: Data?],
                                   settings: HumSettings?) throws {
        let (before, beforeMedia) = ConfigBridge.export(boards: model.store.boards())
        let beforeSettings = currentSettings()
        let model = self.model
        let plan = MergePlanner.plan(existing: before, incoming: document, mode: .replace)
        try model.store.change("Replace Everything", undo: { _ in
            // The saved pictures are ready to store as they are.
            try? ImportService(model: model).replaceEverything(with: before, media: beforeMedia,
                                                               prepared: beforeMedia.mapValues { Optional($0) },
                                                               settings: beforeSettings)
        }) {
            try ConfigBridge.apply(plan, media: media, prepared: prepared, in: model.context)
        }
        // Display and voice settings only come along with "Replace everything".
        if let settings {
            model.settings.apply(settings)
            model.applySpeechSettings()
        }
        model.goHome()
    }

    /// iOS can only draw SVG pictures (e.g. Mulberry symbols in a hand-made file) asynchronously, with
    /// WebKit, so imported SVGs are converted to JPEG just after the import. It also runs at launch, which
    /// repairs SVGs saved by older builds of Hum or synced from another device. Not an undo step of its
    /// own: undoing the import removes these tiles anyway.
    private static func liveTile(_ id: UUID, in context: ModelContext) -> Tile? {
        var descriptor = FetchDescriptor<Tile>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    static func renderImportedSVGs(_ model: AppModel) async {
        guard !model.isConvertingSVGs else { return }
        model.isConvertingSVGs = true
        defer { model.isConvertingSVGs = false }
        let ids = ((try? model.context.fetch(FetchDescriptor<Tile>())) ?? [])
            .filter { $0.imageData.map(ImageProcessing.isSVG) ?? false }.map(\.id)
        for (i, id) in ids.enumerated() {
            // Fetched again at every step: while a picture is drawn, an import or a synced change can
            // delete the tile, and reading a deleted tile's picture crashes SwiftData.
            guard let svg = liveTile(id, in: model.context)?.imageData, ImageProcessing.isSVG(svg) else { continue }
            let jpeg = await ImageProcessing.tileImageDataAllowingSVG(from: svg)
            guard let tile = liveTile(id, in: model.context) else { continue }
            // Saved at once and kept off the undo stack: Undo right after an import must undo the import.
            model.store.withoutUndo {
                tile.imageData = jpeg  // nil if it can't be drawn: no picture beats a broken one
                if jpeg == nil { tile.imageCredit = nil }
            }
            // A big set (e.g. a whole page set) has hundreds: show them as they come.
            if i % 50 == 49 { model.scheduleSnapshotRefresh() }
            await Task.yield()
        }
        if !ids.isEmpty { model.scheduleSnapshotRefresh() }
    }

    // MARK: Suggested tiles

    /// Suggested tiles (AI helper, pasted phrases) that the parent saw listed and chose to add.
    /// They take free spots on the board being edited (or the folder the AI named), else the
    /// "needs a spot" tray. Same Merge path as a file, so existing tiles never move or disappear.
    @discardableResult
    func addSuggested(_ tiles: [ProposedTile], targetBoardID: UUID?, source: String) throws -> MergePlanner.Summary {
        let existing = ConfigBridge.export(boards: model.store.boards()).document
        let document = ProposalChecker.document(from: tiles, targetBoardID: targetBoardID, existing: existing)
        let issues = HumValidator.semanticIssues(in: document)
        if issues.contains(where: { $0.severity == .error }) { throw HumConfigError.invalid(issues) }
        let pending = prepare(loaded: LoadedConfig(document: document, media: [:], warnings: issues), fileName: source)
        try apply(pending, mode: .merge)
        return pending.merge.summary
    }

    // MARK: Export

    /// The whole setup (or one board) as `.hum` bytes.
    func exportData(boardID: UUID? = nil) throws -> Data {
        let (document, media) = exportContents(boardID: boardID)
        return try HumPackage.write(document, media: media)
    }

    /// What an export contains, before it's zipped (zipping can run in the background).
    func exportContents(boardID: UUID? = nil) -> (document: HumDocument, media: [String: Data]) {
        var boards = model.store.boards()
        if let boardID { boards = boards.filter { $0.id == boardID } }
        var (document, media) = ConfigBridge.export(boards: boards)
        if boardID == nil {
            document.settings = currentSettings()
            document.name = String(localized: "Hum boards")
        }
        return (document, media)
    }

    func currentSettings() -> HumSettings {
        let s = model.settings
        return HumSettings(
            voice: HumVoice(identifier: s.voiceIdentifier, rate: s.rate, pitch: s.pitch, volume: s.volume),
            showLabels: s.showLabels, labelPosition: s.labelPosition, sentenceStrip: s.sentenceStrip,
            appearance: s.appearance, retrigger: s.retrigger, activation: s.activation)
    }

    static func exportFileName(boardName: String? = nil) -> String {
        let date = Date.now.formatted(.iso8601.year().month().day())
        if let boardName { return "\(boardName) \(date).hum" }
        return String(localized: "Hum boards \(date)", comment: "The name of an exported file; the date is like 2026-10-12.") + ".hum"
    }

    // MARK: Backups

    /// How many "Before import" backups are kept (the newest).
    nonisolated static let backupsToKeep = 3

    nonisolated static var backupsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
    }

    /// Saves the current setup before "Replace everything". Keeps the newest `backupsToKeep`.
    func writeBackup(in dir: URL = Self.backupsDirectory) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        try exportData().write(to: dir.appendingPathComponent("Before import \(stamp).hum"), options: .atomic)
        Self.pruneBackups(in: dir)
    }

    /// The backups, newest first (their names start with the date and time).
    nonisolated static func backups(in dir: URL = backupsDirectory) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.filter { $0.pathExtension == "hum" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Removes all but the newest `keep` backups (after a backup, and once at launch).
    nonisolated static func pruneBackups(keep: Int = backupsToKeep, in dir: URL = backupsDirectory) {
        for old in backups(in: dir).dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// How many backups there are and how big they are together (Share & sync).
    nonisolated static func backupsSummary(in dir: URL = backupsDirectory) -> (count: Int, bytes: Int64) {
        let files = backups(in: dir)
        let bytes = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return (files.count, bytes)
    }

    /// "Delete backups" in Share & sync. The boards themselves aren't touched.
    nonisolated static func deleteBackups(in dir: URL = backupsDirectory) throws {
        for file in backups(in: dir) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
