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
                .onChanged { _ in if holdTask == nil { beginHold() } }
                .onEnded { _ in cancelHold() }
        )
        .accessibilityLabel("Grown-up settings")
        .accessibilityHint("Press and hold for 3 seconds")
        .accessibilityAction(named: "Open grown-up settings") { onUnlock() }
        .accessibilityIdentifier("editGate")
    }

    private func beginHold() {
        withAnimation(.linear(duration: Self.holdDuration)) { progress = 1 }
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.holdDuration))
            guard !Task.isCancelled else { return }
            holdTask = nil
            progress = 0
            onUnlock()
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }
}
