// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import Observation

/// Records a parent saying a tile's phrase, keeping the real intonation (it carries meaning for gestalts).
///
/// The microphone permission is asked only when the parent taps Record. Recordings stay on the device
/// (and in the family's own iCloud if sync is on). They are never sent to any AI model.
@MainActor
@Observable
final class PhraseRecorder {
    enum State: Equatable { case idle, recording, denied, failed }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private let url = FileManager.default.temporaryDirectory.appendingPathComponent("hum-recording.m4a")

    static let maxDuration: TimeInterval = 15

    /// Asks for the microphone (first time only) and starts recording.
    func start() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            state = .denied
            return
        }
        #if os(iOS)
        // Recording needs playAndRecord; `finish()` puts the session back to playback.
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            try? FileManager.default.removeItem(at: url)
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record(forDuration: Self.maxDuration) else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            state = .recording
            elapsed = 0
            timer = Task { @MainActor in
                while !Task.isCancelled, self.state == .recording {
                    try? await Task.sleep(for: .milliseconds(100))
                    self.elapsed = self.recorder?.currentTime ?? self.elapsed
                    if self.recorder?.isRecording == false { break }
                }
            }
        } catch {
            state = .failed
        }
    }

    /// Stops and returns the recorded file's bytes (m4a), or nil if nothing was recorded.
    func finish() -> Data? {
        recorder?.stop()
        recorder = nil
        timer?.cancel()
        state = .idle
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        #endif
        return try? Data(contentsOf: url)
    }

    func play(_ data: Data) {
        player?.stop()
        player = try? AVAudioPlayer(data: data)
        player?.play()
    }
}
