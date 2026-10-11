// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CoreData
import CloudKit
import Observation

/// Plain-language iCloud sync status for the parent: is this device signed in, and when did boards last
/// go up to iCloud or come down from it. Reads the sync events SwiftData's CloudKit mirroring posts.
@MainActor
@Observable
final class SyncMonitor {
    struct EventInfo: Equatable {
        var date: Date
        var succeeded: Bool
        var error: String?
    }

    enum Account: Equatable {
        case unknown, available, noAccount, restricted, temporarilyUnavailable
        case failed(String)

        var description: String {
            switch self {
            case .unknown: return "Checking…"
            case .available: return "Signed in"
            case .noAccount: return "Not signed in to iCloud on this device"
            case .restricted: return "iCloud is restricted on this device (Screen Time or a profile)"
            case .temporarilyUnavailable: return "iCloud is temporarily unavailable. Check Settings → your name → iCloud."
            case .failed(let reason): return "Couldn't check iCloud: \(reason)"
            }
        }
    }

    private(set) var account: Account = .unknown
    private(set) var lastSetup: EventInfo?
    private(set) var lastExport: EventInfo?
    private(set) var lastImport: EventInfo?
    /// True while an upload or download is running.
    private(set) var busy = false

    @ObservationIgnored private var observer: NSObjectProtocol?
    let containerID: String

    init(containerID: String = Persistence.cloudKitContainerID) {
        self.containerID = containerID
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let info = (type: event.type, end: event.endDate, ok: event.succeeded,
                        error: event.error.map(Self.describe))
            MainActor.assumeIsolated { self?.record(info.type, end: info.end, succeeded: info.ok, error: info.error) }
        }
    }

    func refreshAccount() async {
        do {
            switch try await CKContainer(identifier: containerID).accountStatus() {
            case .available: account = .available
            case .noAccount: account = .noAccount
            case .restricted: account = .restricted
            case .temporarilyUnavailable: account = .temporarilyUnavailable
            case .couldNotDetermine: account = .unknown
            @unknown default: account = .unknown
            }
        } catch {
            account = .failed(error.localizedDescription)
        }
    }

    private func record(_ type: NSPersistentCloudKitContainer.EventType, end: Date?, succeeded: Bool, error: String?) {
        // An event is posted when it starts (no end date) and again when it finishes.
        guard let end else {
            if type != .setup { busy = true }
            return
        }
        busy = false
        let info = EventInfo(date: end, succeeded: succeeded, error: error)
        switch type {
        case .setup: lastSetup = info
        case .export: lastExport = info
        case .import: lastImport = info
        @unknown default: break
        }
    }

    /// CloudKit errors in words a parent can act on.
    nonisolated static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        switch ck.code {
        case .notAuthenticated: return "Not signed in to iCloud."
        case .quotaExceeded: return "iCloud storage is full."
        case .networkUnavailable, .networkFailure: return "No internet connection. Changes will sync when you're back online."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud is busy. It will try again by itself."
        case .badContainer, .missingEntitlement, .permissionFailure:
            return "This copy of Hum isn't set up for iCloud (\(ck.code.rawValue)). Developers: check the iCloud container and signing."
        case .partialFailure: return "Some changes didn't sync yet. It will try again by itself."
        default: return "\(ck.localizedDescription) (code \(ck.code.rawValue))"
        }
    }
}
