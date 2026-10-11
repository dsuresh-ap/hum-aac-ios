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
                    if once.claim() { continuation.resume(returning: box.take()) }
                } else {
                    box.append(PCMClip.convert(pcm))
                }
            }
            // Safety net: some voices never send the final empty buffer. Give up after 10 s.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                if once.claim() { continuation.resume(returning: box.take()) }
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

/// Collects samples from synthesizer callbacks (any thread).
nonisolated private final class SampleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    func append(_ more: [Float]) { lock.withLock { samples += more } }
    func take() -> [Float] { lock.withLock { samples } }
}

nonisolated private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool { lock.withLock { if claimed { return false }; claimed = true; return true } }
}
