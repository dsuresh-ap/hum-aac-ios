// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import Vision
@testable import Hum

/// A classifier that always gives the same guesses.
private struct FakeClassifier: ObjectClassifying {
    let guesses: [ObjectGuess]
    func classify(_ imageData: Data) async -> [ObjectGuess] { guesses }
}

private func guess(_ identifier: String, _ confidence: Double) -> ObjectGuess {
    ObjectGuess(identifier: identifier, confidence: confidence)
}

/// Names guessed from a photo are plain words, the useful ones first, and only ideas for the parent.
@Suite("Object names from photos")
struct ObjectNamerTests {
    @Test func readableNames() {
        #expect(ObjectNamer.readable("dog") == "dog")
        #expect(ObjectNamer.readable("food_bowl") == "food bowl")
        #expect(ObjectNamer.readable("chair_other") == "chair")
        #expect(ObjectNamer.readable("balloon_hotair") == "hot air balloon")
        #expect(ObjectNamer.readable("adult_cat") == "cat")
        #expect(ObjectNamer.readable("Ice_Cream") == "ice cream")
    }

    @Test func skipsBroadGroups() {
        // What Vision says about an eagle photo: the whole family tree, all equally sure.
        let eagle = [guess("animal", 0.99), guess("bird", 0.99), guess("eagle", 0.99), guess("raptor", 0.99)]
        #expect(ObjectNamer.suggestions(from: eagle) == ["bird", "eagle"])
    }

    @Test func mostLikelyFirstAndAtMostThree() {
        let guesses = [guess("cat", 0.4), guess("dog", 0.9), guess("ball", 0.6), guess("leash", 0.5), guess("bone", 0.3)]
        #expect(ObjectNamer.suggestions(from: guesses) == ["dog", "ball", "leash"])
        #expect(ObjectNamer.suggestions(from: guesses, limit: 1) == ["dog"])
    }

    @Test func dropsUnsureGuessesAndRepeats() {
        let guesses = [guess("adult_cat", 0.8), guess("cat", 0.8), guess("kitten", 0.19)]
        #expect(ObjectNamer.suggestions(from: guesses) == ["cat"])
        #expect(ObjectNamer.suggestions(from: [guess("animal", 0.9), guess("mammal", 0.9)]).isEmpty)
        #expect(ObjectNamer.suggestions(from: []).isEmpty)
    }

    @Test func englishOnlyForNow() async {
        let fake = FakeClassifier(guesses: [guess("dog", 0.9)])
        #expect(await ObjectNamer.names(for: Data(), using: fake, language: "en") == ["dog"])
        #expect(await ObjectNamer.names(for: Data(), using: fake, language: "en-GB") == ["dog"])
        #expect(await ObjectNamer.names(for: Data(), using: fake, language: "de").isEmpty)
        #expect(await ObjectNamer.names(for: Data(), using: fake, language: "zh-Hans").isEmpty)
    }

    @Test func aPictureVisionCantReadGivesNoNames() async {
        #expect(await ObjectNamer.names(for: Data("not a picture".utf8), using: VisionObjectClassifier(), language: "en").isEmpty)
    }

    /// Catches typos: every name in the cleanup lists is one Vision really uses.
    @Test func listsUseVisionsOwnNames() throws {
        let known = Set(try VNClassifyImageRequest().supportedIdentifiers())
        #expect(Set(ObjectNamer.renamed.keys).subtracting(known).isEmpty)
        #expect(ObjectNamer.broad.subtracting(known).isEmpty)
    }
}
