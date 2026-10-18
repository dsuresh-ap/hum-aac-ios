// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
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
}
