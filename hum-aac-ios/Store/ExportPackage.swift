// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import HumConfig

extension ImportService {
    /// The `.hum` file for sending (AirDrop, a nearby device). What goes in is read here, on the main
    /// actor where the boards live; zipping, the slow part, runs off it so the screen keeps moving and
    /// can show "Preparing…" and a Cancel button. (Importing has its own work off the main actor.)
    func exportPackage(boardID: UUID? = nil) async throws -> Data {
        // Let "Preparing…" draw before the boards are read.
        try await Task.sleep(for: .milliseconds(50))
        // UI tests: slow enough to see the "Preparing…" state.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingSlowExport") {
            try await Task.sleep(for: .seconds(10))
        }
        let (document, media) = exportContents(boardID: boardID)
        let data = try await Self.zipPackage(document, media: media)
        try Task.checkCancellation()
        return data
    }

    nonisolated static func zipPackage(_ document: HumDocument, media: [String: Data]) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { try HumPackage.write(document, media: media) }.value
    }
}
