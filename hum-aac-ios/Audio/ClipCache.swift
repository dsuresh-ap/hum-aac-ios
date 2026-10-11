// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CryptoKit

/// What a pre-rendered speech clip depends on. If any part changes, the clip is rendered again.
nonisolated struct SpeechKey: Hashable, Sendable {
    var text: String
    var voiceIdentifier: String
    var rate: Double
    var pitch: Double

    /// Stable file name for the disk cache. Includes a format version so old caches are ignored.
    var fileName: String {
        let raw = "v1|\(Int(AudioConstants.sampleRate))|\(voiceIdentifier)|\(rate)|\(pitch)|\(text)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined() + ".f32"
    }
}

/// Two-level cache for rendered speech: memory (LRU, size-capped) and disk (Caches/Speech, rebuildable).
///
/// The tap path only touches `memory(for:)`, a dictionary lookup. Disk reads and writes happen on a
/// background queue.
@MainActor
final class ClipCache {
    private var clips: [SpeechKey: PCMClip] = [:]
    private var lastUsed: [SpeechKey: UInt64] = [:]
    private var clock: UInt64 = 0
    private(set) var bytes = 0
    let byteLimit: Int
    /// Evicted clips stay alive a little longer, so the render thread never frees memory mid-play.
    private var graveyard: [(PCMClip, Date)] = []

    nonisolated let directory: URL

    init(byteLimit: Int = 64 * 1024 * 1024, directory: URL? = nil) {
        self.byteLimit = byteLimit
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Speech", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    var count: Int { clips.count }

    /// Fast path for taps.
    func memory(for key: SpeechKey) -> PCMClip? {
        guard let clip = clips[key] else { return nil }
        clock += 1
        lastUsed[key] = clock
        return clip
    }

    func insert(_ clip: PCMClip, for key: SpeechKey) {
        if let old = clips[key] { bytes -= old.byteCount; retire(old) }
        clips[key] = clip
        bytes += clip.byteCount
        clock += 1
        lastUsed[key] = clock
        evictIfNeeded(protecting: key)
    }

    func removeAll() {
        for clip in clips.values { retire(clip) }
        clips.removeAll()
        lastUsed.removeAll()
        bytes = 0
    }

    private func evictIfNeeded(protecting key: SpeechKey) {
        while bytes > byteLimit, clips.count > 1,
              let victim = lastUsed.filter({ $0.key != key }).min(by: { $0.value < $1.value })?.key,
              let clip = clips.removeValue(forKey: victim) {
            lastUsed[victim] = nil
            bytes -= clip.byteCount
            retire(clip)
        }
    }

    private func retire(_ clip: PCMClip) {
        let now = Date.now
        graveyard.removeAll { now.timeIntervalSince($0.1) > 60 }
        graveyard.append((clip, now))
    }

    // MARK: Disk

    nonisolated func loadFromDisk(_ key: SpeechKey) -> PCMClip? {
        let url = directory.appendingPathComponent(key.fileName)
        guard let data = try? Data(contentsOf: url), data.count >= MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { raw in
            PCMClip(copying: raw.bindMemory(to: Float.self))
        }
    }

    nonisolated func saveToDisk(_ samples: [Float], key: SpeechKey) {
        let url = directory.appendingPathComponent(key.fileName)
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: url, options: .atomic)
    }
}
