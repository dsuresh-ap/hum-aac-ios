// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Hidden developer screen (parent mode only): measured tap-to-sound latency on this device.
/// Numbers live in memory only. Nothing is saved or sent.
struct DeveloperLatencyView: View {
    @Environment(AppModel.self) private var model
    @State private var stressRunning = false
    @State private var stressTaps = 0

    var body: some View {
        let probe = model.speech.latency
        Form {
            Section("Try it") {
                Text("Tap the pad. Each touch plays a pre-rendered phrase and records how long it took to reach the speaker.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TestPad { tapTime in model.speech.speak("Let's go!", tapTime: tapTime) }
                    .frame(height: 140)
                    .accessibilityIdentifier("latencyPad")
            }
            Section("Results (last 200 taps)") {
                if let s = probe.stats {
                    LabeledContent("Taps measured", value: "\(s.count)")
                    LabeledContent("Fastest", value: ms(s.min))
                    LabeledContent("Median", value: ms(s.median))
                    LabeledContent("95th percentile", value: ms(s.p95))
                    LabeledContent("Slowest", value: ms(s.max))
                    LabeledContent("Goal (cached tile)", value: "under 30 ms")
                } else {
                    Text("No taps yet.").foregroundStyle(.secondary)
                }
                LabeledContent("Taps that had to speak live", value: "\(probe.uncachedTaps)")
                LabeledContent("Phrases waiting to render", value: "\(model.speech.pendingRenders)")
                LabeledContent("Phrases in memory", value: "\(model.speech.cache.count)")
                LabeledContent("Audio engine restarts", value: "\(model.speech.engine.restartCount)")
                Button("Clear results") { probe.reset() }
            }
            Section("Stress test") {
                Text("Plays 20 taps a second for 30 seconds. Every tap should make a sound, with no pops.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(stressRunning ? "Running… \(stressTaps) taps" : "Start stress test") { runStress() }
                    .disabled(stressRunning)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Latency")
        .onAppear { model.speech.prepare(["Let's go!"]) }
    }

    private func ms(_ v: Double) -> String { String(format: "%.1f ms", v) }

    private func runStress() {
        stressRunning = true
        stressTaps = 0
        Task { @MainActor in
            let phrases = ["Let's go!", "Stop!", "Uh oh!", "Hi!"]
            model.speech.prepare(phrases)
            await model.speech.waitUntilIdle()
            for i in 0..<(20 * 30) {
                model.speech.speak(phrases[i % phrases.count])
                stressTaps += 1
                try? await Task.sleep(for: .milliseconds(50))
            }
            stressRunning = false
        }
    }
}

/// A plain touch-down pad for latency testing.
private struct TestPad: View {
    let onTap: (UInt64) -> Void
    @State private var pressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(pressed ? Color.accentColor.opacity(0.35) : Color.accentColor.opacity(0.15))
            .overlay(Text("Tap here").font(.title2.weight(.semibold)))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    onTap(mach_absolute_time())
                    pressed = true
                }
                .onEnded { _ in pressed = false })
    }
}
