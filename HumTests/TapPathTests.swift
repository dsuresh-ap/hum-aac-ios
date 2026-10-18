// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import Foundation
import Testing
@testable import Hum

/// A short recording, like the tile editor makes (AAC in an .m4a file).
func recordingData(seconds: Double = 0.3, pitch: Float = 0.05) throws -> Data {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("TapPathTests-\(UUID().uuidString).m4a")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let frames = AVAudioFrameCount(44_100 * seconds)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    let samples = try #require(buffer.floatChannelData?[0])
    for i in 0..<Int(frames) { samples[i] = 0.3 * sin(Float(i) * pitch) }
    try write(buffer, to: url)
    return try Data(contentsOf: url)
}

/// Writes and closes the file (it closes when `file` goes away at the end of this function).
private func write(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
    let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                            AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
    try file.write(from: buffer)
}

/// From a tap to sound: a ready clip goes straight to the sampler, a phrase not ready yet speaks live
/// and is rendered for next time, and a parent's recording wins over the voice.
@MainActor
@Suite("Tap to speech")
struct TapPathTests {
    func service() -> SpeechService {
        SpeechService(voice: .init(identifier: "test-voice", rate: 0.5, pitch: 1, volume: 1))
    }

    @Test func aReadyPhraseGoesStraightToTheSampler() {
        let speech = service()
        speech.cache.insert(PCMClip(samples: [Float](repeating: 0.2, count: 4800)), for: speech.key(for: "Let's go!"))
        #expect(speech.isReady("Let's go!"))
        speech.speak("Let's go!")
        #expect(speech.engine.sampler.isPlaying)
        #expect(speech.latency.uncachedTaps == 0)
        #expect(speech.pendingRenders == 0, "nothing left to render")
    }

    @Test func aPhraseNotReadyYetSpeaksLiveAndIsRenderedForNextTime() {
        let speech = service()
        speech.speak("A phrase said for the very first time")
        #expect(speech.latency.uncachedTaps == 1)
        #expect(!speech.engine.sampler.isPlaying, "the live voice speaks this one")
        #expect(speech.pendingRenders == 1, "queued to render for next time")
    }

    @Test func aParentsRecordingWinsOverTheVoice() async throws {
        let speech = service()
        await speech.loadRecording(id: "tile-1", data: try recordingData())
        speech.speak("Let's go!", recordingID: "tile-1")
        #expect(speech.engine.sampler.isPlaying)
        #expect(speech.latency.uncachedTaps == 0, "the recording plays, not the live voice")
        #expect(speech.pendingRenders == 0)
        // A recording that isn't loaded (yet): the voice says the words meanwhile.
        speech.speak("Let's go!", recordingID: "not-loaded")
        #expect(speech.latency.uncachedTaps == 1)
    }

    @Test func aRecordingThatIsntAudioIsIgnored() async {
        let speech = service()
        await speech.loadRecording(id: "broken", data: Data("not audio".utf8))
        speech.speak("Hi!", recordingID: "broken")
        #expect(speech.latency.uncachedTaps == 1, "the words are said instead")
    }

    // MARK: Through the board

    func tileWithRecording(_ model: AppModel, spokenText: String = "Let's go!") throws -> (Tile, Data) {
        let tile = try #require(model.home.placedTiles.first { $0.linkedBoardID == nil && !$0.spokenText.isEmpty })
        let audio = try recordingData()
        tile.spokenText = spokenText
        tile.audioData = audio
        model.rebuildSnapshot()
        return (tile, audio)
    }

    func cell(_ model: AppModel, _ id: UUID) throws -> BoardSnapshot.Cell {
        try #require(model.snapshot?.cells.joined().compactMap { $0 }.first { $0.id == id })
    }

    @Test func aTileWithARecordingPlaysItWhenTapped() async throws {
        let model = makeModel()
        let (tile, audio) = try tileWithRecording(model)
        let key = try #require(try cell(model, tile.id).recordingKey)
        #expect(key == AppModel.recordingKey(tile.id, audio))
        await model.speech.loadRecording(id: key, data: audio)  // what the board does when it shows
        model.tap(try cell(model, tile.id), tapTime: 0)
        #expect(model.speech.latency.uncachedTaps == 0)
        #expect(model.history.latest(1).first?.spokenText == "Let's go!")
    }

    /// A new recording gets a new key, so the old one is never played by mistake.
    @Test func reRecordingChangesTheKey() throws {
        let id = UUID()
        let first = try recordingData(pitch: 0.05)
        let second = try recordingData(pitch: 0.09)
        #expect(AppModel.recordingKey(id, first) == AppModel.recordingKey(id, first))
        #expect(AppModel.recordingKey(id, first) != AppModel.recordingKey(id, second))
        #expect(AppModel.recordingKey(id, first) != AppModel.recordingKey(UUID(), first))
    }

    /// Shortcuts and Siri: a recorded tile plays its recording even when its board isn't showing.
    @Test func aRecordingPlaysFromShortcutsToo() async throws {
        let model = makeModel()
        let (tile, _) = try tileWithRecording(model)
        model.goHome()
        #expect(await model.say(tileID: tile.id))
        #expect(model.speech.latency.uncachedTaps == 0)
    }

    // MARK: Sentence strip

    @Test func theStripCollectsTapsOnlyWhenItsOn() throws {
        let model = makeModel()
        let cells = model.snapshot?.cells.joined().compactMap { $0 }.filter { !$0.spokenText.isEmpty && $0.linkedBoardID == nil } ?? []
        try #require(cells.count >= 2)
        model.tap(cells[0], tapTime: 0)
        #expect(model.strip.isEmpty, "off by default")
        model.settings.sentenceStrip = true
        model.tap(cells[0], tapTime: 0)
        model.tap(cells[1], tapTime: 0)
        #expect(model.strip.map(\.id) == [cells[0].id, cells[1].id])
        let taps = model.speech.latency.uncachedTaps
        model.speakStrip()
        #expect(model.speech.latency.uncachedTaps == taps + 1, "the strip speaks as one phrase")
        model.clearStrip()
        #expect(model.strip.isEmpty)
        model.speakStrip()
        #expect(model.speech.latency.uncachedTaps == taps + 1, "an empty strip says nothing")
    }
}

/// The grown-up gate: hold the lock for 3 seconds.
@Suite("Edit gate")
struct EditGateTests {
    let hold = EditGateButton.holdDuration

    /// A touch timestamp the way the system gives it: seconds since the device started.
    func touch(secondsAgo: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: ProcessInfo.processInfo.systemUptime - secondsAgo)
    }

    @Test func theHoldCountsFromTheTouch() {
        // iPadOS held the touch back for a moment: that moment counts.
        let held = EditGateButton.secondsSinceTouch(touch(secondsAgo: 0.8))
        #expect(held >= 0.8 && held < 1.5)
        #expect(EditGateButton.remainingHold(touchedAt: touch(secondsAgo: 0.8)) <= hold - 0.8)
        // A wall-clock timestamp works too.
        let wall = EditGateButton.secondsSinceTouch(Date.now.addingTimeInterval(-1))
        #expect(wall >= 1 && wall < 1.5)
    }

    /// A timestamp that doesn't look like a recent touch never shortens the hold.
    @Test func oddTimestampsCountAsJustNow() {
        #expect(EditGateButton.secondsSinceTouch(.distantPast) == 0)
        #expect(EditGateButton.secondsSinceTouch(.distantFuture) == 0)
        #expect(EditGateButton.secondsSinceTouch(touch(secondsAgo: hold + 5)) == 0)
        #expect(EditGateButton.remainingHold(touchedAt: .distantPast) == hold)
    }

    /// However late the touch arrives, the ring still fills for a moment before grown-up mode opens.
    @Test func thereIsAlwaysAMomentLeft() {
        #expect(hold == 3)
        let remaining = EditGateButton.remainingHold(touchedAt: touch(secondsAgo: hold - 0.01))
        #expect(remaining >= 0.2 && remaining < 0.25)
    }
}
