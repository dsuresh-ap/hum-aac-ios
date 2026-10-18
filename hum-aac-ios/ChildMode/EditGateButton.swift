// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The parent gate: press and hold a small lock for 3 seconds while a ring fills.
///
/// It is not a puzzle or a test, just a deliberate action a child is unlikely to do by accident.
/// For full lock-down, parents use Apple's Guided Access (tip shown once in parent mode).
struct EditGateButton: View {
    static let holdDuration: Double = 3
    let onUnlock: () -> Void

    @State private var progress: Double = 0
    @State private var holdTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.tileText.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.tileText.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.tileText.opacity(0.45))
        }
        .frame(width: 40, height: 40)
        .padding(6)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in if holdTask == nil { beginHold(touchedAt: value.time) } }
                .onEnded { _ in cancelHold() }
        )
        .accessibilityLabel("Grown-up settings")
        .accessibilityHint("Press and hold for 3 seconds")
        .accessibilityAction(named: "Open grown-up settings") { onUnlock() }
        .accessibilityIdentifier("editGate")
    }

    /// Counts from when the finger touched, not from when the touch reached Hum: near the top edge
    /// iPadOS holds touches back for its own gestures (about 0.8 s in the simulator), so a 3-second hold
    /// used to need much longer (BUGS.md, HUM-044).
    private func beginHold(touchedAt: Date) {
        let remaining = Self.remainingHold(touchedAt: touchedAt)
        progress = 1 - remaining / Self.holdDuration
        withAnimation(.linear(duration: remaining)) { progress = 1 }
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            holdTask = nil
            progress = 0
            onUnlock()
        }
    }

    /// How much longer the finger must stay down. At least 0.2 s, so the ring is always seen filling.
    static func remainingHold(touchedAt: Date) -> TimeInterval {
        holdDuration - min(secondsSinceTouch(touchedAt), holdDuration - 0.2)
    }

    /// A gesture's `time` is the touch's timestamp: seconds since the device started, stored as a date
    /// after 2001-01-01. Anything that doesn't look like a recent touch counts as "just now".
    static func secondsSinceTouch(_ touchedAt: Date) -> TimeInterval {
        let age = ProcessInfo.processInfo.systemUptime - touchedAt.timeIntervalSinceReferenceDate
        if (0..<holdDuration).contains(age) { return age }
        let wallClock = Date.now.timeIntervalSince(touchedAt)
        return (0..<holdDuration).contains(wallClock) ? wallClock : 0
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }
}
