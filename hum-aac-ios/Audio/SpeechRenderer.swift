// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation

/// Renders text to PCM with `AVSpeechSynthesizer.write(_:toBufferCallback:)`, ahead of time.
///
/// Renders run one at a time (the synthesizer is not reliable with parallel writes). Callbacks arrive on
/// a synthesizer thread, so the accumulator is a small locked box.
@MainActor
final class SpeechRenderer {
    private let synthesizer = AVSpeechSynthesizer()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Renders `key` to trimmed mono 48 kHz samples. Returns an empty array if the voice produced nothing.
    func render(_ key: SpeechKey) async -> [Float] {
        await acquire()
        defer { release() }

        let utterance = SpeechRenderer.utterance(for: key)
        let box = SampleBox()
        let samples: [Float] = await withCheckedContinuation { (continuation: CheckedContinuation<[Float], Never>) in
            let once = OnceFlag()
            // @Sendable: the callback runs on a synthesizer thread, not the main actor.
            synthesizer.write(utterance) { @Sendable buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    // A zero-length buffer marks the end of the utterance.
                    if once.claim() { continuation.resume(returning: box.resampled()) }
                } else {
                    box.append(pcm)
                }
            }
            // Safety net: some voices never send the final empty buffer. Give up after 10 s.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                if once.claim() { continuation.resume(returning: box.resampled()) }
            }
        }
        return PCMClip.trimSilence(samples)
    }

    static func utterance(for key: SpeechKey) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: key.text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: key.voiceIdentifier) ?? AVSpeechSynthesisVoice(language: nil)
        utterance.rate = Float(AVSpeechUtteranceMinimumSpeechRate
            + (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) * Float(key.rate))
        utterance.pitchMultiplier = Float(key.pitch)
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        return utterance
    }

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

/// Collects the synthesizer's buffers (any thread) at their own sample rate, then resamples the whole
/// phrase once.
///
/// The synthesizer sends ~11 ms chunks (256 frames at 22.05 kHz). Resampling each chunk with its own
/// converter left a tiny glitch at every chunk edge, heard as static or hiss, most of all in the quiet
/// end of a phrase (BUGS.md, HUM-048).
nonisolated final class SampleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double?

    func append(_ pcm: AVAudioPCMBuffer) {
        let n = Int(pcm.frameLength)
        // The first channel; in interleaved data its samples are `step` apart.
        let step = pcm.format.isInterleaved ? Int(pcm.format.channelCount) : 1
        let chunk: [Float]
        if let data = pcm.floatChannelData {
            chunk = (0..<n).map { data[0][$0 * step] }
        } else if let data = pcm.int16ChannelData {
            chunk = (0..<n).map { Float(data[0][$0 * step]) / 32768 }
        } else if let data = pcm.int32ChannelData {
            chunk = (0..<n).map { Float(data[0][$0 * step]) / 2_147_483_648 }
        } else {
            return
        }
        lock.withLock {
            if sampleRate == nil { sampleRate = pcm.format.sampleRate }
            samples += chunk
        }
    }

    /// Everything so far, as one mono 48 kHz clip.
    func resampled() -> [Float] {
        let (all, rate) = lock.withLock { (samples, sampleRate) }
        guard let rate, !all.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(all.count)),
              let data = buffer.floatChannelData else { return [] }
        all.withUnsafeBufferPointer { data[0].update(from: $0.baseAddress!, count: all.count) }
        buffer.frameLength = AVAudioFrameCount(all.count)
        return PCMClip.convert(buffer)
    }
}

nonisolated private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool { lock.withLock { if claimed { return false }; claimed = true; return true } }
}
