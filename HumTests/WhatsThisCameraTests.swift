// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import os
import Testing
@testable import Hum

/// Guesses for one picture, always the same.
private struct FakeClassifier: ObjectClassifying {
    let identifiers: [String]
    func classify(_ imageData: Data) async -> [ObjectGuess] {
        identifiers.map { ObjectGuess(identifier: $0, confidence: 0.9) }
    }
}

/// The child's "What's this?" camera: off until a parent turns it on, and a guess speaks only when tapped.
@MainActor
@Suite("What's this? camera")
struct WhatsThisCameraTests {
    @Test func offByDefaultAndRemembered() {
        let defaults = UserDefaults(suiteName: "HumTests-\(UUID().uuidString)")!
        #expect(DeviceSettings(defaults: defaults).whatsThisCamera == false)
        DeviceSettings(defaults: defaults).whatsThisCamera = true
        #expect(DeviceSettings(defaults: defaults).whatsThisCamera == true)
    }

    @Test func availableOnlyInEnglishWithACamera() {
        #expect(WhatsThisCamera.availability(language: "en", hasCamera: true) == .available)
        #expect(WhatsThisCamera.availability(language: "en-GB", hasCamera: true) == .available)
        #expect(WhatsThisCamera.availability(language: "de", hasCamera: true) == .notInEnglish)
        #expect(WhatsThisCamera.availability(language: "zh-Hans", hasCamera: false) == .notInEnglish)
        #expect(WhatsThisCamera.availability(language: "en", hasCamera: false) == .noCamera)
    }

    @Test func buttonNeedsTheSettingAndTheCamera() {
        #expect(WhatsThisCamera.showsButton(settingOn: true, availability: .available, cameraAllowed: true))
        #expect(!WhatsThisCamera.showsButton(settingOn: false, availability: .available, cameraAllowed: true))
        // Permission taken away later in Settings: no button, so the child never meets a prompt.
        #expect(!WhatsThisCamera.showsButton(settingOn: true, availability: .available, cameraAllowed: false))
        #expect(!WhatsThisCamera.showsButton(settingOn: true, availability: .notInEnglish, cameraAllowed: true))
        #expect(!WhatsThisCamera.showsButton(settingOn: true, availability: .noCamera, cameraAllowed: true))
    }

    @Test func theModelFollowsTheSetting() {
        let model = makeModel()
        model.usesFakeCamera = true
        #expect(!model.showsWhatsThisButton, "Off until a parent turns it on")
        model.settings.whatsThisCamera = true
        #expect(model.showsWhatsThisButton)
    }

    @Test func aTappedGuessSpeaksIntoHistoryAndMovesNothing() async throws {
        let model = makeModel()
        let before = model.layout(model.home)
        let words = await ObjectNamer.names(for: Data(), using: FakeClassifier(identifiers: ["animal", "dog", "food_bowl"]),
                                            language: "en")
        #expect(words == ["dog", "food bowl"])
        #expect(model.history.recent(1).isEmpty, "Guessing says nothing by itself")
        model.sayGuess(try #require(words.last))
        let entry = try #require(model.history.recent(1).first)
        #expect(entry.spokenText == "food bowl" && entry.label == "food bowl")
        #expect(entry.function == nil && entry.colorHex == nil)
        #expect(model.layout(model.home) == before)
        #expect(model.strip.isEmpty, "A guess isn't a tile, so it stays out of the sentence strip")
    }

    @Test func anEmptyGuessSaysNothing() {
        let model = makeModel()
        model.sayGuess("  ")
        #expect(model.history.recent(1).isEmpty)
    }

    /// A child tapping the same word again and again gets one history entry with a count, at the end,
    /// like a tile. Spaces around a word don't make it a different one.
    @Test func repeatedGuessesCountLikeATile() throws {
        let model = makeModel()
        model.sayGuess("dog")
        model.sayGuess(" dog\n")
        model.sayGuess("dog")
        let entry = try #require(model.history.latest(12).last)
        #expect(model.history.entries.count == 1)
        #expect(entry.spokenText == "dog" && entry.count == 3)
        let hi = try #require(model.snapshot?.cells.joined().compactMap { $0 }.first { $0.label == "hi" })
        model.tap(hi, tapTime: 0)
        #expect(model.history.latest(12).map(\.spokenText) == ["dog", hi.spokenText], "oldest first, newest last")
    }

    /// Without the stand-in camera the button needs the device's own camera and its permission (the
    /// simulator has neither), so a child never meets a camera Hum may not use.
    @Test func theRealCameraNeedsPermission() {
        let model = makeModel()
        model.settings.whatsThisCamera = true
        #expect(model.showsWhatsThisButton == (WhatsThisCamera.deviceHasCamera && WhatsThisCamera.cameraAllowed))
        #expect(model.whatsThisAvailability == (WhatsThisCamera.deviceHasCamera ? .available : .noCamera))
        model.usesFakeCamera = true
        #expect(model.showsWhatsThisButton)
    }
}

/// The camera screen's steps, with a stand-in camera: one picture per tap, words or a calm "Try again",
/// "Take another", and Close turning the camera off.
@MainActor
@Suite("What's this? camera: taking pictures")
struct WhatsThisSessionTests {
    func setUp(_ answers: [[String]] = [["animal", "dog", "food_bowl"]]) -> (AppModel, FakeCamera, WhatsThisSession) {
        let model = makeModel()
        model.objectClassifier = TakingTurnsClassifier(answers)
        let camera = FakeCamera(picture: testPicture())
        return (model, camera, WhatsThisSession(camera: camera))
    }

    @Test func aPictureGetsItsWords() async {
        let (model, camera, session) = setUp()
        await session.start(model)
        #expect(session.step == .live)
        #expect(camera.isRunning)
        await session.snap(model)
        #expect(session.step == .words(["dog", "food bowl"]))
        #expect(session.photo != nil)
        #expect(!camera.isRunning, "the camera rests while the words show")
        #expect(model.history.entries.isEmpty, "nothing speaks until a word is tapped")
    }

    @Test func takeAnotherAfterTryAgain() async {
        let (model, camera, session) = setUp([[], ["dog"]])
        await session.start(model)
        await session.snap(model)
        #expect(session.step == .noWords)
        await session.retake(model)
        #expect(session.step == .live)
        #expect(session.photo == nil)
        #expect(camera.isRunning && camera.starts == 2)
        await session.snap(model)
        #expect(session.step == .words(["dog"]))
    }

    @Test func aPictureThatCantBeReadIsATryAgain() async {
        let (model, camera, session) = setUp()
        camera.picture = nil
        await session.start(model)
        await session.snap(model)
        #expect(session.step == .noWords)
        #expect(session.photo == nil)
        #expect(!camera.isRunning)

        camera.picture = Data("not a picture".utf8)
        await session.retake(model)
        await session.snap(model)
        #expect(session.step == .noWords)
    }

    /// "Take another" only means something once a picture has its words (or none).
    @Test func takeAnotherOnlyAfterAPicture() async {
        let (model, camera, session) = setUp()
        await session.retake(model)
        #expect(session.step == .starting)
        await session.start(model)
        await session.retake(model)
        #expect(session.step == .live && camera.starts == 1)
    }

    @Test func aSecondTapTakesNoSecondPicture() async {
        let (model, camera, session) = setUp([["dog"], ["cat"]])
        await session.start(model)
        let first = Task { await session.snap(model) }
        let second = Task { await session.snap(model) }
        await first.value
        await second.value
        #expect(camera.captures == 1)
        #expect(session.step == .words(["dog"]))
    }

    @Test func noCameraSaysSoAndTakesNothing() async {
        let (model, camera, session) = setUp()
        camera.works = false
        await session.start(model)
        #expect(session.step == .noCamera)
        await session.snap(model)
        #expect(session.step == .noCamera && camera.captures == 0)
    }

    @Test func closeTurnsTheCameraOffAtEveryStep() async {
        // While live.
        var (model, camera, session) = setUp()
        await session.start(model)
        session.close()
        #expect(!camera.isRunning)
        // With words showing.
        (model, camera, session) = setUp()
        await session.start(model)
        await session.snap(model)
        session.close()
        #expect(!camera.isRunning)
        // After "Take another".
        (model, camera, session) = setUp()
        await session.start(model)
        await session.snap(model)
        await session.retake(model)
        #expect(camera.isRunning)
        session.close()
        #expect(!camera.isRunning)
    }

    /// The screen can close before its start has run (SwiftUI starts `.task` work a moment after the
    /// screen appears). Close still wins: the camera never comes on after it, and nothing starts it again.
    @Test func closeBeforeTheCameraStartsWins() async {
        let (model, camera, session) = setUp()
        let starting = Task { await session.start(model) }
        session.close()
        await starting.value
        #expect(!camera.isRunning)
        await session.retake(model)
        await session.start(model)
        #expect(!camera.isRunning)
    }
}

// MARK: Fakes

/// A camera that takes the same picture every time. Counts what it's asked to do.
nonisolated final class FakeCamera: WhatsThisCameraDevice, @unchecked Sendable {
    private struct State {
        var picture: Data?
        var works = true
        var isRunning = false
        var starts = 0
        var captures = 0
    }
    private let state: OSAllocatedUnfairLock<State>

    init(picture: Data?) { state = OSAllocatedUnfairLock(initialState: State(picture: picture)) }

    var picture: Data? {
        get { state.withLock(\.picture) }
        set { state.withLock { $0.picture = newValue } }
    }
    var works: Bool {
        get { state.withLock(\.works) }
        set { state.withLock { $0.works = newValue } }
    }
    var isRunning: Bool { state.withLock(\.isRunning) }
    var starts: Int { state.withLock(\.starts) }
    var captures: Int { state.withLock(\.captures) }

    func start() async -> Bool {
        state.withLock { s in
            s.starts += 1
            s.isRunning = s.works
            return s.works
        }
    }

    func stop() { state.withLock { $0.isRunning = false } }

    func capture() async -> Data? {
        state.withLock { s in
            guard s.isRunning else { return nil }
            s.captures += 1
            return s.picture
        }
    }
}

/// Gives each picture the next set of guesses.
private nonisolated final class TakingTurnsClassifier: ObjectClassifying {
    private let answers: [[String]]
    private let calls = OSAllocatedUnfairLock(initialState: 0)

    init(_ answers: [[String]]) { self.answers = answers }

    func classify(_ imageData: Data) async -> [ObjectGuess] {
        let call = calls.withLock { count in
            defer { count += 1 }
            return count
        }
        return answers[call % answers.count].map { ObjectGuess(identifier: $0, confidence: 0.9) }
    }
}

/// A small JPEG, like a camera picture.
func testPicture() -> Data? {
    guard let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    context.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    return context.makeImage().flatMap { ImageProcessing.jpegData($0) }
}
