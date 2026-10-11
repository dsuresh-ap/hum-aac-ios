// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import os

/// A tiny real-time sampler: the heart of Hum's low-latency audio.
///
/// A tap only flips a few fields in `State` under an unfair lock (microseconds). The next render
/// cycle, about 5 ms later, starts the clip at sample 0. Because the sampler mixes its own voices,
/// it can do sample-accurate fades, instant retrigger, overlap and "let it finish" without ever
/// stopping or restarting the audio engine.
///
/// Real-time rules for `render`: no allocation, no Objective-C messaging, no I/O, no logging. The
/// only lock is the unfair lock, which the main thread holds for a few microseconds at most.
nonisolated final class VoiceSampler: @unchecked Sendable {
    enum Mode: Sendable { case restart, finish, overlap }

    struct Voice {
        var clip: PCMClip?
        var position = 0
        /// When > 0 the voice is fading out; it stops when this reaches 0.
        var fadeOutRemaining = 0
        var fadingOut = false
        var startOrder: UInt64 = 0
        var token: UInt64 = 0
        var reportedStart = false
        var gain: Float = 1
    }

    struct State {
        var voices = [Voice](repeating: Voice(), count: AudioConstants.maxVoices)
        var mode: Mode = .restart
        var order: UInt64 = 0
        /// "Let speech finish" mode: the most recent tap waiting for the current phrase to end.
        var queued: (clip: PCMClip, token: UInt64, gain: Float)?
        /// Latency probe: token → host time of the render cycle that started it (fixed-size ring).
        var starts = [(token: UInt64, hostTime: UInt64, bufferFrames: UInt32)](repeating: (0, 0, 0), count: 64)
        var startsHead = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var mode: Mode {
        get { lock.withLock { $0.mode } }
        set { lock.withLock { $0.mode = newValue } }
    }

    /// Plays `clip` now according to the current mode. Never drops a tap.
    func trigger(_ clip: PCMClip, token: UInt64, gain: Float = 1) {
        lock.withLock { state in
            switch state.mode {
            case .restart:
                Self.fadeOutAll(&state)
                Self.start(clip, token: token, gain: gain, in: &state)
            case .overlap:
                Self.start(clip, token: token, gain: gain, in: &state)
            case .finish:
                if state.voices.contains(where: { $0.clip != nil && !$0.fadingOut }) {
                    state.queued = (clip, token, gain)  // latest tap wins; it plays when the current one ends
                } else {
                    Self.start(clip, token: token, gain: gain, in: &state)
                }
            }
        }
    }

    /// Fades out everything (used when live speech takes over, or when the app goes to background).
    func stopAll() {
        lock.withLock { state in
            state.queued = nil
            Self.fadeOutAll(&state)
        }
    }

    var isPlaying: Bool { lock.withLock { $0.voices.contains { $0.clip != nil } } }

    /// Returns the host time at which the render thread started the clip for `token`, if it has.
    func startInfo(for token: UInt64) -> (hostTime: UInt64, bufferFrames: UInt32)? {
        lock.withLock { state in
            state.starts.first(where: { $0.token == token }).map { ($0.hostTime, $0.bufferFrames) }
        }
    }

    // MARK: - State helpers (called with the lock held)

    private static func fadeOutAll(_ state: inout State) {
        for i in state.voices.indices where state.voices[i].clip != nil && !state.voices[i].fadingOut {
            state.voices[i].fadingOut = true
            state.voices[i].fadeOutRemaining = AudioConstants.fadeOutFrames
        }
    }

    private static func start(_ clip: PCMClip, token: UInt64, gain: Float, in state: inout State) {
        state.order &+= 1
        // A free voice, else the oldest fading voice, else the oldest voice (voice stealing).
        // Plain loops on purpose: this can run on the render thread, so no temporary arrays.
        var index = -1
        for i in state.voices.indices where state.voices[i].clip == nil {
            index = i
            break
        }
        if index < 0 {
            for i in state.voices.indices where state.voices[i].fadingOut {
                if index < 0 || state.voices[i].startOrder < state.voices[index].startOrder { index = i }
            }
        }
        if index < 0 {
            index = 0
            for i in state.voices.indices where state.voices[i].startOrder < state.voices[index].startOrder { index = i }
        }
        state.voices[index] = Voice(clip: clip, position: 0, fadeOutRemaining: 0, fadingOut: false,
                                    startOrder: state.order, token: token, reportedStart: false, gain: gain)
    }

    // MARK: - Render (real-time thread)

    /// Fills `frameCount` mono frames. Called by the AVAudioSourceNode on the audio I/O thread.
    func render(into output: UnsafeMutablePointer<Float>, frameCount: Int, hostTime: UInt64) {
        output.update(repeating: 0, count: frameCount)
        // Unchecked: the closure captures the raw output pointer, which is only used inside the lock.
        lock.withLockUnchecked { state in
            for v in state.voices.indices {
                guard let clip = state.voices[v].clip else { continue }
                var voice = state.voices[v]
                if !voice.reportedStart {
                    voice.reportedStart = true
                    state.starts[state.startsHead] = (voice.token, hostTime, UInt32(frameCount))
                    state.startsHead = (state.startsHead + 1) % state.starts.count
                }
                let src = clip.samples
                var frame = 0
                while frame < frameCount && voice.position < src.count {
                    var g = voice.gain
                    if voice.position < AudioConstants.fadeInFrames {
                        g *= Float(voice.position) / Float(AudioConstants.fadeInFrames)
                    }
                    if voice.fadingOut {
                        if voice.fadeOutRemaining <= 0 { break }
                        g *= Float(voice.fadeOutRemaining) / Float(AudioConstants.fadeOutFrames)
                        voice.fadeOutRemaining -= 1
                    }
                    output[frame] += src[voice.position] * g
                    voice.position += 1
                    frame += 1
                }
                let finished = voice.position >= src.count || (voice.fadingOut && voice.fadeOutRemaining <= 0)
                if finished {
                    state.voices[v] = Voice()
                } else {
                    state.voices[v] = voice
                }
            }
            // "Let speech finish": start the queued tap once nothing else is speaking.
            if let queued = state.queued, !state.voices.contains(where: { $0.clip != nil && !$0.fadingOut }) {
                state.queued = nil
                Self.start(queued.clip, token: queued.token, gain: queued.gain, in: &state)
            }
        }
        // Soft clip so overlapping voices never wrap into harsh distortion.
        for i in 0..<frameCount where abs(output[i]) > 1 { output[i] = output[i] > 0 ? 1 : -1 }
    }
}
