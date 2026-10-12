// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

/// Measures tap-to-sound latency on real devices. Kept in memory only; nothing in the app shows it since
/// the developer screen was removed (BUGS.md, HUM-022).
///
/// latency = (render cycle that started the clip − touch time) + one I/O buffer + output latency.
/// Only the last 200 samples are kept, in memory. Nothing is stored or sent anywhere; this is not analytics.
@MainActor
@Observable
final class LatencyProbe {
    struct Sample: Identifiable {
        let id = UUID()
        let milliseconds: Double
        let cached: Bool
    }

    private(set) var samples: [Sample] = []
    @ObservationIgnored private var uncachedCount = 0
    private(set) var uncachedTaps = 0

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func seconds(fromHostTicks ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    func track(token: UInt64, tapTime: UInt64, sampler: VoiceSampler, outputLatency: TimeInterval, cached: Bool) {
        Task { @MainActor in
            // Poll briefly for the render thread's stamp (it arrives within a few milliseconds).
            for _ in 0..<50 {
                if let start = sampler.startInfo(for: token) {
                    let renderDelay = start.hostTime > tapTime ? Self.seconds(fromHostTicks: start.hostTime - tapTime) : 0
                    let buffer = Double(start.bufferFrames) / AudioConstants.sampleRate
                    self.add(Sample(milliseconds: (renderDelay + buffer + outputLatency) * 1000, cached: cached))
                    return
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    func recordUncached(tapTime: UInt64) {
        uncachedTaps += 1
    }

    private func add(_ sample: Sample) {
        samples.append(sample)
        if samples.count > 200 { samples.removeFirst(samples.count - 200) }
    }

    func reset() {
        samples.removeAll()
        uncachedTaps = 0
    }

    struct Stats {
        var count: Int, min: Double, median: Double, p95: Double, max: Double
    }

    var stats: Stats? {
        let values = samples.map(\.milliseconds).sorted()
        guard !values.isEmpty else { return nil }
        func pct(_ p: Double) -> Double { values[min(values.count - 1, Int(Double(values.count - 1) * p))] }
        return Stats(count: values.count, min: values[0], median: pct(0.5), p95: pct(0.95), max: values.last!)
    }
}
