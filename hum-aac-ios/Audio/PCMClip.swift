// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation

/// Immutable mono Float32 audio at `AudioConstants.sampleRate`, ready for the real-time render thread.
///
/// The samples live in one manually allocated block. The render thread only reads it: no allocation,
/// no Objective-C, no locks. Clips are kept alive by `ClipCache` (and a short grace list after
/// eviction), so the render thread is never the one that frees the memory.
nonisolated final class PCMClip: @unchecked Sendable {
    let samples: UnsafeMutableBufferPointer<Float>
    var frameCount: Int { samples.count }
    var duration: TimeInterval { Double(frameCount) / AudioConstants.sampleRate }
    var byteCount: Int { frameCount * MemoryLayout<Float>.size }

    init(copying source: UnsafeBufferPointer<Float>) {
        samples = .allocate(capacity: max(source.count, 1))
        if source.isEmpty {
            samples[0] = 0
        } else {
            _ = samples.initialize(from: source)
        }
    }

    convenience init(samples array: [Float]) {
        self.init(copying: array.withUnsafeBufferPointer { $0 })
    }

    deinit { samples.deallocate() }

    // MARK: Building clips

    /// Converts any PCM buffer to our canonical format (mono Float32 at 48 kHz).
    static func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard buffer.frameLength > 0 else { return [] }
        let target = AudioConstants.format
        if buffer.format == target, let data = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        }
        guard let converter = AVAudioConverter(from: buffer.format, to: target) else { return [] }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }

    /// Removes leading and trailing near-silence. Speech synthesizers often add 50–150 ms of silence
    /// at the start, which a child hears as lag. We keep ~3 ms before the first sound.
    static func trimSilence(_ samples: [Float], threshold: Float = 0.003) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) > threshold }),
              let last = samples.lastIndex(where: { abs($0) > threshold }) else { return [] }
        let pad = Int(AudioConstants.sampleRate * 0.003)
        let tail = Int(AudioConstants.sampleRate * 0.040)  // keep a little release so endings aren't clipped
        let start = max(0, first - pad)
        let end = min(samples.count, last + tail)
        return Array(samples[start..<end])
    }

    /// Decodes an audio file (a parent's recording) into a clip.
    static func decode(fileData: Data) -> PCMClip? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try fileData.write(to: url)
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: buffer)
            let samples = trimSilence(convert(buffer))
            return samples.isEmpty ? nil : PCMClip(samples: samples)
        } catch {
            return nil
        }
    }
}

nonisolated enum AudioConstants {
    /// All clips use one format. The mixer converts to the hardware rate, so a Bluetooth route change
    /// (which can switch the hardware to 16/24 kHz) never invalidates the cache.
    static let sampleRate: Double = 48_000
    static let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    /// Fade when cutting a sound (prevents clicks on fast retriggers).
    static let fadeOutFrames = Int(sampleRate * 0.003)
    /// Tiny fade-in at the start of each clip (prevents a DC click on the first sample).
    static let fadeInFrames = Int(sampleRate * 0.002)
    static let maxVoices = 8
}
