// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import AVFoundation
@testable import Hum

/// Drives the real-time sampler offline, buffer by buffer, exactly as the audio thread would.
struct SamplerHarness {
    let sampler = VoiceSampler()
    static let bufferFrames = 240  // 5 ms at 48 kHz, our preferred I/O buffer
    var output: [Float] = []
    var host: UInt64 = 1

    mutating func render(frames: Int) {
        var remaining = frames
        var buffer = [Float](repeating: 0, count: Self.bufferFrames)
        while remaining > 0 {
            let n = min(remaining, Self.bufferFrames)
            buffer.withUnsafeMutableBufferPointer { sampler.render(into: $0.baseAddress!, frameCount: n, hostTime: host) }
            output += buffer.prefix(n)
            host += 1
            remaining -= n
        }
    }

    /// Largest jump between neighbouring samples: a click/pop shows up as a big jump.
    var maxStep: Float {
        zip(output, output.dropFirst()).map { abs($1 - $0) }.max() ?? 0
    }
}

/// A steady, loud clip: worst case for clicks when it is cut off.
func loudClip(seconds: Double = 1) -> PCMClip {
    PCMClip(samples: [Float](repeating: 0.6, count: Int(AudioConstants.sampleRate * seconds)))
}

@Suite("Audio sampler")
struct AudioSamplerTests {
    @Test func everyTapStartsAtTwentyTapsASecondForThirtySeconds() {
        var h = SamplerHarness()
        h.sampler.mode = .restart
        let clip = loudClip(seconds: 0.8)
        let framesBetweenTaps = Int(AudioConstants.sampleRate / 20)
        var dropped = 0
        for token in 1...UInt64(20 * 30) {
            h.sampler.trigger(clip, token: token)
            h.render(frames: framesBetweenTaps)
            if h.sampler.startInfo(for: token) == nil { dropped += 1 }
            if h.output.count > 48_000 { h.output.removeFirst(h.output.count - 48_000) }  // keep memory flat
        }
        #expect(dropped == 0)
        #expect(h.maxStep < 0.05, "a retrigger produced a click")
    }

    @Test func restartCutsTheOldSoundWithAFadeNotAClick() {
        var h = SamplerHarness()
        h.sampler.trigger(loudClip(), token: 1)
        h.render(frames: 4800)
        let cutAt = h.output.count
        h.sampler.trigger(loudClip(), token: 2)
        h.render(frames: 4800)
        #expect(h.maxStep < 0.05)
        // During the 3 ms crossfade both voices sound briefly; after it, only the new one remains.
        let afterFade = h.output[(cutAt + 2 * AudioConstants.fadeOutFrames)...]
        #expect(afterFade.allSatisfy { abs($0 - 0.6) < 0.001 })
    }

    @Test func overlapPlaysBothAtOnce() {
        var h = SamplerHarness()
        h.sampler.mode = .overlap
        h.sampler.trigger(loudClip(), token: 1)
        h.render(frames: 480)
        h.sampler.trigger(loudClip(), token: 2)
        h.render(frames: 4800)
        #expect((h.output.max() ?? 0) > 1.0 - 0.001)  // 0.6 + 0.6, soft-clipped at 1.0
        #expect(h.sampler.startInfo(for: 2) != nil)
    }

    @Test func finishModePlaysTheLatestTapAfterTheCurrentOne() {
        var h = SamplerHarness()
        h.sampler.mode = .finish
        h.sampler.trigger(loudClip(seconds: 0.2), token: 1)
        h.render(frames: 480)
        h.sampler.trigger(loudClip(seconds: 0.2), token: 2)
        h.sampler.trigger(loudClip(seconds: 0.2), token: 3)  // latest wins
        h.render(frames: 4800)
        #expect(h.sampler.startInfo(for: 2) == nil)
        h.render(frames: 9600)
        #expect(h.sampler.startInfo(for: 3) != nil)
    }

    @Test func clipsStartWithoutAClickFromSilence() {
        var h = SamplerHarness()
        h.render(frames: 480)
        h.sampler.trigger(loudClip(), token: 1)
        h.render(frames: 480)
        #expect(h.maxStep < 0.05)
    }

    @Test func stopAllFadesEverything() {
        var h = SamplerHarness()
        h.sampler.trigger(loudClip(), token: 1)
        h.render(frames: 480)
        h.sampler.stopAll()
        h.render(frames: 480)
        #expect(!h.sampler.isPlaying)
        #expect(h.output.suffix(100).allSatisfy { $0 == 0 })
    }
}

@MainActor
@Suite("Speech cache")
struct SpeechCacheTests {
    @Test func trimRemovesLeadingSilence() {
        let samples = [Float](repeating: 0, count: 4800) + [Float](repeating: 0.5, count: 4800) + [Float](repeating: 0, count: 4800)
        let trimmed = PCMClip.trimSilence(samples)
        #expect(trimmed.count < 4800 + 2400)
        #expect(trimmed.prefix(200).contains { $0 > 0.4 })
    }

    @Test func keyChangesWhenVoiceSettingsChange() {
        let a = SpeechKey(text: "Hi!", voiceIdentifier: "v1", rate: 0.5, pitch: 1)
        var b = a
        b.rate = 0.6
        #expect(a.fileName != b.fileName)
        var c = a
        c.voiceIdentifier = "v2"
        #expect(a.fileName != c.fileName)
    }

    @Test func lruEvictsTheOldestClipOverTheLimit() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID())")
        let cache = ClipCache(byteLimit: 1_000_000, directory: dir)
        let clip = { PCMClip(samples: [Float](repeating: 0.1, count: 100_000)) }  // 400 KB each
        let keys = (0..<3).map { SpeechKey(text: "p\($0)", voiceIdentifier: "v", rate: 0.5, pitch: 1) }
        cache.insert(clip(), for: keys[0])
        cache.insert(clip(), for: keys[1])
        _ = cache.memory(for: keys[0])  // touch 0, so 1 is now the oldest
        cache.insert(clip(), for: keys[2])
        #expect(cache.memory(for: keys[1]) == nil)
        #expect(cache.memory(for: keys[0]) != nil)
        #expect(cache.bytes <= 1_000_000)
    }

    @Test func diskCacheRoundTrips() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID())")
        let cache = ClipCache(directory: dir)
        let key = SpeechKey(text: "Hi!", voiceIdentifier: "v", rate: 0.5, pitch: 1)
        cache.saveToDisk([0.1, 0.2, 0.3], key: key)
        let loaded = cache.loadFromDisk(key)
        #expect(loaded.map { Array($0.samples) } == [0.1, 0.2, 0.3])
    }

    @Test func voiceChangeTriggersReRender() {
        let speech = SpeechService(voice: .init(identifier: "a", rate: 0.5, pitch: 1, volume: 1))
        let before = speech.key(for: "Hi!")
        speech.update(voice: .init(identifier: "b", rate: 0.5, pitch: 1, volume: 1))
        #expect(speech.key(for: "Hi!") != before)
        #expect(!speech.isReady("Hi!"))
    }

    @Test func engineSurvivesRestarts() {
        let engine = AudioEngine()
        engine.start()
        for _ in 0..<5 { engine.restart() }  // what an interruption or route change does
        #expect(engine.restartCount == 5)
        engine.pause()
        engine.start()
    }
}

@Suite("Voices")
struct VoiceTests {
    @Test func stylePresetsRoundTrip() {
        for style in VoiceStyle.allCases where style != .custom {
            let v = style.values!
            #expect(VoiceStyle.matching(rate: v.rate, pitch: v.pitch) == style)
        }
        #expect(VoiceStyle.matching(rate: 0.61, pitch: 1.7) == .custom)
    }

    @Test func youngerIsHigherAndSlower() {
        let natural = VoiceStyle.natural.values!, younger = VoiceStyle.younger.values!
        #expect(younger.pitch > natural.pitch)
        #expect(younger.rate < natural.rate)
    }

    @Test func catalogNeverOffersNoveltyVoicesAndPutsBestFirst() {
        let voices = VoiceCatalog.voices()
        #expect(!voices.contains { $0.voiceTraits.contains(.isNoveltyVoice) })
        let qualities = voices.map(\.quality.rawValue)
        #expect(qualities == qualities.sorted(by: >))
    }
}
