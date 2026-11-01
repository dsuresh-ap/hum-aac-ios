// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

extension GeometryProxy {
    /// Where the screen folds across this view while a folding iPhone is partly folded, with the system's
    /// margins for touch targets, in this view's coordinates. Nil when nothing folds here.
    var fold: CGRect? {
        // Fold regions came with the iOS 27.1 SDK (SwiftUICore 8.0.85.29). Older SDKs, like CI's Xcode 26,
        // build without them: no fold.
        #if os(iOS) && canImport(SwiftUICore, _version: 8.0.85.29)
        if #available(iOS 27.1, *) {
            return reservedRegions(kind: .division).first(where: \.isActive)?.frame
        }
        #endif
        return nil
    }
}

extension View {
    /// Centers this across the full width, or on the trailing side of a fold that runs top to bottom.
    func centeredOffTheFold() -> some View { modifier(CenteredOffTheFold()) }
}

private struct CenteredOffTheFold: ViewModifier {
    @State private var fold: CGRect?

    func body(content: Content) -> some View {
        content
            .padding(.leading, upright(fold).map(\.maxX) ?? 0)
            .frame(maxWidth: .infinity)
            // Measured around the padding, so moving the content never moves the fold.
            .onGeometryChange(for: CGRect?.self) { geo in
                geo.fold.flatMap { $0.minX > 0 && $0.maxX < geo.size.width ? $0 : nil }
            } action: { fold = $0 }
    }

    private func upright(_ fold: CGRect?) -> CGRect? { fold.flatMap { $0.height >= $0.width ? $0 : nil } }
}
