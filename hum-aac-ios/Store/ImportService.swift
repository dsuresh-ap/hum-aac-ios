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

/// A file that has been read and checked, waiting for the parent to choose Merge or Replace.
struct PendingImport: Identifiable {
    let id = UUID()
    let fileName: String
    let loaded: LoadedConfig
    let merge: MergePlanner.Plan
    let replace: MergePlanner.Plan
    /// Set when this came from the Shortcuts/Siri queue; the file is removed once the parent decides.
    var queueFile: URL? = nil
}

/// Reads, previews and applies imports; writes exports and backups.
///
/// Every import (files, AirDrop, "Open in Hum", AI, App Intents) ends in `apply`, which goes through
/// the merge planner, so no import path can move or delete tiles behind the parent's back.
@MainActor
struct ImportService {
    let model: AppModel

    /// Reads a file and plans both options. Throws `HumConfigError` with friendly text.
    func prepare(url: URL) throws -> PendingImport {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw HumConfigError.badPackage("Hum couldn't read the file.")
        }
        return try prepare(data: data, fileName: url.lastPathComponent)
    }

    func prepare(data: Data, fileName: String) throws -> PendingImport {
        let loaded = try HumConfigLoader.load(data)
        return prepare(loaded: loaded, fileName: fileName)
    }

    /// Also used by the AI helper and App Intents with documents they built.
    func prepare(loaded: LoadedConfig, fileName: String) -> PendingImport {
        let existing = ConfigBridge.export(boards: model.store.boards()).document
        return PendingImport(
            fileName: fileName, loaded: loaded,
            merge: MergePlanner.plan(existing: existing, incoming: loaded.document, mode: .merge),
            replace: MergePlanner.plan(existing: existing, incoming: loaded.document, mode: .replace))
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
            case .backingUp: "Saving a backup of your boards…"
            case .pictures(_, 0): "Getting ready…"
            case .pictures(let done, let total): "Preparing pictures… \(done) of \(total)"
            case .saving: "Saving your boards…"
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
        try model.store.change(mode == .merge ? "Import" : "Replace Everything") {
            try ConfigBridge.apply(plan, media: pending.loaded.media, prepared: prepared, in: model.context)
        }
        // Display and voice settings only come along with "Replace everything".
        if mode == .replace, let settings = pending.loaded.document.settings {
            model.settings.apply(settings)
            model.applySpeechSettings()
        }
        if mode == .replace || model.fetchBoard(model.currentBoardID ?? UUID()) == nil {
            model.goHome()
        } else {
            model.scheduleSnapshotRefresh()
        }
        Task { await Self.renderImportedSVGs(model) }
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
            model.context.undoManager?.disableUndoRegistration()
            tile.imageData = jpeg  // nil if it can't be drawn: no picture beats a broken one
            model.context.undoManager?.enableUndoRegistration()
            // A big import (e.g. a whole page set) has hundreds: save and show them as they come.
            if i % 50 == 49 {
                try? model.context.save()
                model.scheduleSnapshotRefresh()
            }
            await Task.yield()
        }
        try? model.context.save()
        model.scheduleSnapshotRefresh()
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
        var boards = model.store.boards()
        if let boardID { boards = boards.filter { $0.id == boardID } }
        var (document, media) = ConfigBridge.export(boards: boards)
        if boardID == nil {
            document.settings = currentSettings()
            document.name = "Hum setup"
        }
        return try HumPackage.write(document, media: media)
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
        return "Hum setup \(date).hum"
    }

    // MARK: Backups

    static var backupsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
    }

    /// Saves the current setup before "Replace everything". Keeps the 10 newest backups.
    func writeBackup() throws {
        let dir = Self.backupsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        try exportData().write(to: dir.appendingPathComponent("Before import \(stamp).hum"), options: .atomic)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for old in files.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(10) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
