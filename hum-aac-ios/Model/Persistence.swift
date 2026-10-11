// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData

/// Builds the SwiftData container.
///
/// iCloud sync (M4) will reuse the same store file with `cloudKitDatabase: .private(...)`, so turning
/// sync on never loses local data. Until then the store is local only (`.none`): no network at all.
enum Persistence {
    static let cloudKitContainerID = "iCloud.com.dhananjaysuresh.hum-aac"

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(HumSchema.models)
        let configuration = ModelConfiguration(
            "Hum",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A broken store must never stop a child from communicating. Fall back to memory so the
            // app still opens (with the starter board), and log for developers. Data recovery is a
            // parent-mode task, not a child-mode crash.
            print("Hum: could not open the store (\(error)). Using a temporary in-memory store.")
            let fallback = ModelConfiguration("HumFallback", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            // Force-try is acceptable: an in-memory store with a valid schema cannot fail to open.
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }
}
