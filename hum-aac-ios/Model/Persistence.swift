// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData

/// Builds the SwiftData container.
///
/// iCloud sync is off until a parent turns it on. On or off, it is the **same store file**, so turning
/// sync on never loses local boards, and turning it off keeps everything on the device. Sync uses only
/// the family's own *private* CloudKit database, which the developers can't see.
enum Persistence {
    /// Must match the iCloud container in hum-aac-ios.entitlements (and the developer portal).
    static let cloudKitContainerID = "iCloud.dhananjaysuresh.hum-aac"

    enum Mode: Equatable { case local, iCloud, memory }

    /// The mode the last `makeContainer` call actually got (it falls back if iCloud isn't available).
    @MainActor static private(set) var activeMode: Mode = .local

    @MainActor
    static func makeContainer(inMemory: Bool = false, iCloud: Bool = false) -> ModelContainer {
        let schema = Schema(HumSchema.models)
        if inMemory {
            activeMode = .memory
            return memoryContainer(schema)
        }
        if iCloud {
            let config = ModelConfiguration("Hum", schema: schema, cloudKitDatabase: .private(cloudKitContainerID))
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                activeMode = .iCloud
                return container
            }
            // Not signed in to iCloud, missing entitlement (unsigned builds), etc.: keep working locally.
            print("Hum: iCloud store unavailable; using the local store.")
        }
        let local = ModelConfiguration("Hum", schema: schema, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, configurations: [local])
            activeMode = .local
            return container
        } catch {
            // A broken store must never stop a child from communicating. Fall back to memory so the app
            // still opens (with the starter board), and log for developers.
            print("Hum: could not open the store (\(error)). Using a temporary in-memory store.")
            activeMode = .memory
            return memoryContainer(schema)
        }
    }

    private static func memoryContainer(_ schema: Schema) -> ModelContainer {
        let config = ModelConfiguration("HumMemory", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // Force-try is acceptable: an in-memory store with a valid schema cannot fail to open.
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
