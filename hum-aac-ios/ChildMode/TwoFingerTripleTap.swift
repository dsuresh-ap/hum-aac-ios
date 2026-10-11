// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

#if os(iOS)
import UIKit

/// The alternative parent gate on iPhone/iPad: a two-finger triple-tap anywhere on the board.
///
/// It sits on top of the grid without blocking it: tiles still get every touch (`cancelsTouchesInView`
/// is false), so a child tapping with two fingers still hears both tiles.
struct TwoFingerTripleTap: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = PassThroughView()
        let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.fire))
        recognizer.numberOfTouchesRequired = 2
        recognizer.numberOfTapsRequired = 3
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        context.coordinator.recognizer = recognizer
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.action = action
        // Attach to the window so the recognizer sees touches that land on the tiles below.
        DispatchQueue.main.async {
            if let window = view.window, let r = context.coordinator.recognizer, r.view !== window {
                window.addGestureRecognizer(r)
            }
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        if let r = coordinator.recognizer { r.view?.removeGestureRecognizer(r) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        var recognizer: UITapGestureRecognizer?
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }

    /// A view that never takes touches itself.
    private final class PassThroughView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
}
#endif
