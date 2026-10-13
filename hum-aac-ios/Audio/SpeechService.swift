// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import Observation

/// What the app calls to make a tile speak. Owns the engine, the cache and the pre-render queue.
///
/// Tap path (`speak`): look up a clip in memory → `sampler.trigger`. Nothing else. If the clip is not
/// ready yet, speak live with `AVSpeechSynthesizer` (target < 150 ms) and render it for next time.
@MainActor
@Observable
final class SpeechService {
    struct VoiceSettings: Equatable {
        var identifier: String
        var rate: Double
        var pitch: Double
        var volume: Double
    }

    @ObservationIgnored let engine = AudioEngine()
    @ObservationIgnored let cache = ClipCache()
    @ObservationIgnored let latency = LatencyProbe()
    @ObservationIgnored private let renderer = SpeechRenderer()
    @ObservationIgnored private let liveSynth = AVSpeechSynthesizer()
    @ObservationIgnored private var nextToken: UInt64 = 0
    @ObservationIgnored private var queue: [SpeechKey] = []
    @ObservationIgnored private var queued: Set<SpeechKey> = []
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    /// Recorded audio clips, decoded when the board loads (keyed by tile ID + data size as a cheap version).
    @ObservationIgnored private var recordings: [String: PCMClip] = [:]

    /// Number of clips waiting to render (for tests).
    private(set) var pendingRenders = 0
    private(set) var voice: VoiceSettings

    init(voice: VoiceSettings? = nil) {
        self.voice = voice ?? VoiceSettings(identifier: SpeechService.defaultVoiceIdentifier(), rate: 0.5, pitch: 1, volume: 1)
    }

    /// The most natural voice installed for the device's language (see `VoiceCatalog`).
    static func defaultVoiceIdentifier() -> String {
        VoiceCatalog.best()?.identifier
            ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())?.identifier
            ?? ""
    }

    func start() { engine.start() }
    func pause() { engine.pause(); liveSynth.stopSpeaking(at: .immediate) }

    var retrigger: VoiceSampler.Mode {
        get { engine.sampler.mode }
        set { engine.sampler.mode = newValue }
    }

    /// Changing voice, rate or pitch changes every cache key, so the current board re-renders.
    func update(voice newVoice: VoiceSettings) {
        guard newVoice != voice else { return }
        voice = newVoice
        engine.volume = Float(newVoice.volume)
    }

    func key(for text: String) -> SpeechKey {
        SpeechKey(text: text, voiceIdentifier: voice.identifier, rate: voice.rate, pitch: voice.pitch)
    }

    func isReady(_ text: String) -> Bool { cache.memory(for: key(for: text)) != nil }

    // MARK: Tap path

    /// Speaks a tile's phrase now. `recording` (a parent's voice) wins over TTS when present.
    /// - Parameter tapTime: `mach_absolute_time()` taken in the touch handler, for the latency probe.
    func speak(_ text: String, recordingID: String? = nil, tapTime: UInt64 = mach_absolute_time()) {
        nextToken &+= 1
        let token = nextToken
        if let recordingID, let clip = recordings[recordingID] {
            stopLive()
            engine.sampler.trigger(clip, token: token)
            latency.track(token: token, tapTime: tapTime, sampler: engine.sampler, outputLatency: engine.outputLatency, cached: true)
            return
        }
        let key = key(for: text)
        if let clip = cache.memory(for: key) {
            stopLive()
            engine.sampler.trigger(clip, token: token)
            latency.track(token: token, tapTime: tapTime, sampler: engine.sampler, outputLatency: engine.outputLatency, cached: true)
        } else {
            // Fallback: live speech now, and render in the background for next time.
            speakLive(key, tapTime: tapTime)
            enqueue([key], urgent: true)
        }
    }

    private func speakLive(_ key: SpeechKey, tapTime: UInt64) {
        engine.sampler.stopAll()
        if retrigger != .overlap, liveSynth.isSpeaking { liveSynth.stopSpeaking(at: .immediate) }
        let utterance = SpeechRenderer.utterance(for: key)
        utterance.volume = Float(voice.volume)
        liveSynth.speak(utterance)
        latency.recordUncached(tapTime: tapTime)
    }

    private func stopLive() {
        if liveSynth.isSpeaking, retrigger != .overlap { liveSynth.stopSpeaking(at: .immediate) }
    }

    // MARK: Pre-rendering

    /// Renders every phrase in `texts` ahead of time (current board first, then linked boards).
    func prepare(_ texts: [String]) {
        enqueue(texts.map(key(for:)), urgent: false)
    }

    /// Decodes recorded clips for the board that is about to show.
    func prepareRecordings(_ items: [(id: String, data: Data)]) {
        for item in items where recordings[item.id] == nil {
            let data = item.data
            Task.detached(priority: .userInitiated) {
                let clip = PCMClip.decode(fileData: data)
                await MainActor.run { if let clip { self.recordings[item.id] = clip } }
            }
        }
    }

    /// Decodes one recording right now, for a phrase said from Shortcuts or Siri (its board may not be showing).
    func loadRecording(id: String, data: Data) async {
        guard recordings[id] == nil else { return }
        let clip = await Task.detached(priority: .userInitiated) { PCMClip.decode(fileData: data) }.value
        if let clip { recordings[id] = clip }
    }

    private func enqueue(_ keys: [SpeechKey], urgent: Bool) {
        for key in keys where !key.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard cache.memory(for: key) == nil, !queued.contains(key) else { continue }
            queued.insert(key)
            if urgent { queue.insert(key, at: 0) } else { queue.append(key) }
        }
        pendingRenders = queue.count
        if renderTask == nil, !queue.isEmpty {
            renderTask = Task { await drain() }
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            let key = queue.removeFirst()
            pendingRenders = queue.count
            // Disk first (fast), then synthesize.
            let cache = self.cache
            let fromDisk = await Task.detached(priority: .utility) { cache.loadFromDisk(key) }.value
            if let fromDisk {
                cache.insert(fromDisk, for: key)
            } else {
                let samples = await renderer.render(key)
                if !samples.isEmpty {
                    cache.insert(PCMClip(samples: samples), for: key)
                    Task.detached(priority: .background) { cache.saveToDisk(samples, key: key) }
                }
            }
            queued.remove(key)
        }
        pendingRenders = 0
        renderTask = nil
    }

    /// Waits until everything queued has rendered (tests).
    func waitUntilIdle() async {
        while let task = renderTask { await task.value }
    }
}
