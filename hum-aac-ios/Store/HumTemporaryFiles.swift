// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The files Hum puts in the temporary folder, and the sweep that removes any an earlier run left
/// behind (Hum was closed while sharing, receiving or recording). They can hold a child's boards, photos
/// and a parent's voice, so none of them should linger.
///
/// - `Export-…/<name>.hum`: a setup being shared (AirDrop, Export). Deleted when sharing ends.
/// - `Nearby-…/received.hum`: a setup arriving from a nearby device. Deleted as soon as it's read, or
///   when the transfer ends any other way.
/// - `hum-recording.m4a`: a phrase being recorded. Deleted once the recording is read.
/// - `<UUID>.m4a`: a recording being decoded. Deleted right after.
nonisolated enum HumTemporaryFiles {
    static let exportPrefix = "Export-"
    static let nearbyPrefix = "Nearby-"
    static let recordingName = "hum-recording.m4a"

    static var directory: URL { FileManager.default.temporaryDirectory }

    /// A new folder for one file. On iOS its files can't be read while the device is locked (except one
    /// already open, so a transfer can finish).
    static func makeFolder(prefix: String, in directory: URL = directory) throws -> URL {
        let folder = directory.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        #if os(iOS)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        #else
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #endif
        return folder
    }

    /// Whether `name` in the temporary folder is one of Hum's.
    static func isHums(_ name: String) -> Bool {
        if name.hasPrefix(exportPrefix) || name.hasPrefix(nearbyPrefix) || name == recordingName { return true }
        // A recording being decoded: "<UUID>.m4a".
        guard name.hasSuffix(".m4a") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }

    /// Removes Hum's items made before `cutoff` (the start of this run), so nothing in use now is touched.
    /// Runs at launch, off the main actor. Returns what it removed.
    @discardableResult
    static func sweep(createdBefore cutoff: Date, in directory: URL = directory) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        var removed: [URL] = []
        for item in items where isHums(item.lastPathComponent) {
            let created = (try? item.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            guard created < cutoff else { continue }
            if (try? FileManager.default.removeItem(at: item)) != nil { removed.append(item) }
        }
        return removed
    }

    /// What launch does: leftovers from earlier runs, and backups beyond the ones kept.
    static func cleanUpAtLaunch(startedAt cutoff: Date) {
        sweep(createdBefore: cutoff)
        ImportService.pruneBackups()
    }
}
