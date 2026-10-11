// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation

/// Owns the one `AVAudioEngine` that stays running while Hum is in the foreground.
///
/// Many AAC apps close and reopen the audio output between taps, which adds lag and a click. Hum never
/// does: the session is configured once and the engine keeps running. It is paused only in the
/// background, and restarted right away after interruptions (calls, Siri) and route changes
/// (headphones, Bluetooth).
@MainActor
final class AudioEngine {
    let sampler = VoiceSampler()
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning = false
    /// Counts restarts (for the developer screen and tests).
    private(set) var restartCount = 0

    init() {
        let sampler = self.sampler
        // The render block runs on the real-time audio thread. It must stay nonisolated and allocation-free.
        let node = AVAudioSourceNode(format: AudioConstants.format) { @Sendable _, timestamp, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let host = timestamp.pointee.mFlags.contains(.hostTimeValid) ? timestamp.pointee.mHostTime : mach_absolute_time()
            sampler.render(into: data, frameCount: Int(frameCount), hostTime: host)
            // Mono source: copy to any extra channels the node was given.
            for i in 1..<buffers.count {
                if let dst = buffers[i].mData { dst.copyMemory(from: data, byteCount: Int(frameCount) * MemoryLayout<Float>.size) }
            }
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: AudioConstants.format)
        observeSystemEvents()
    }

    // MARK: Lifecycle

    /// Configures the session (iOS) and starts the engine. Safe to call repeatedly.
    func start() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback: speech plays even with the ring/silent switch on silent. A child's voice is
            // not a notification sound.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("Hum audio: session setup failed: \(error)")
        }
        #endif
        guard !engine.isRunning else {
            isRunning = true
            return
        }
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
            print("Hum audio: engine failed to start: \(error)")
        }
    }

    /// Background: stop rendering. We do not deactivate the session between taps, only here.
    func pause() {
        sampler.stopAll()
        engine.pause()
        isRunning = false
    }

    /// Rebuilds the connection and starts again (after a route change, reset or interruption).
    func restart() {
        restartCount += 1
        engine.stop()
        if let node = sourceNode {
            engine.connect(node, to: engine.mainMixerNode, format: AudioConstants.format)
        }
        start()
    }

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    /// Output latency after our samples leave the mixer (device + converter), in seconds.
    var outputLatency: TimeInterval {
        #if os(iOS)
        return AVAudioSession.sharedInstance().outputLatency
        #else
        return engine.outputNode.presentationLatency
        #endif
    }

    // MARK: System events

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        // Engine-level change (both platforms): the hardware format or device changed.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        })
        #if os(iOS)
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.restart() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.engine.isRunning else { return }
                self.restart()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        })
        #endif
    }
}
