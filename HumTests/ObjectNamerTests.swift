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
        // A zebra photo: the sky behind it counts once, not as "sky" and "blue sky".
        let zebra = [guess("animal", 0.99), guess("zebra", 0.99), guess("outdoor", 0.26), guess("sky", 0.26), guess("blue_sky", 0.26)]
        #expect(ObjectNamer.suggestions(from: zebra) == ["zebra", "sky"])
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

/// Holds each guess until the test finishes it, so a test chooses which photo's guess ends first.
private actor HeldClassifier: ObjectClassifying {
    private var waiting: [Data: CheckedContinuation<[ObjectGuess], Never>] = [:]
    private var ready: [Data: [ObjectGuess]] = [:]

    func classify(_ imageData: Data) async -> [ObjectGuess] {
        if let guesses = ready.removeValue(forKey: imageData) { return guesses }
        return await withCheckedContinuation { waiting[imageData] = $0 }
    }

    func finish(_ imageData: Data, with identifiers: [String]) {
        let guesses = identifiers.map { ObjectGuess(identifier: $0, confidence: 0.9) }
        if let waiter = waiting.removeValue(forKey: imageData) {
            waiter.resume(returning: guesses)
        } else {
            ready[imageData] = guesses
        }
    }
}

/// The tile editor's "Looks like:" row shows only the names for the photo on the tile right now.
@MainActor
@Suite("Photo name ideas in the tile editor")
struct PhotoNameIdeasTests {
    let older = Data([1])
    let newer = Data([2])

    @Test func aLateGuessForAnOlderPhotoIsDropped() async {
        let ideas = PhotoNameIdeas()
        let classifier = HeldClassifier()
        ideas.pictureChanged(to: older)
        let first = Task { await ideas.guess(older, using: classifier, language: "en") }
        ideas.pictureChanged(to: newer)
        let second = Task { await ideas.guess(newer, using: classifier, language: "en") }
        await classifier.finish(newer, with: ["dog"])
        await second.value
        #expect(ideas.names == ["dog"])
        await classifier.finish(older, with: ["cat"])
        await first.value
        #expect(ideas.names == ["dog"], "the older photo's guess came last and is dropped")
    }

    @Test func anEarlyGuessForAnOlderPhotoIsDroppedToo() async {
        let ideas = PhotoNameIdeas()
        let classifier = HeldClassifier()
        ideas.pictureChanged(to: older)
        let first = Task { await ideas.guess(older, using: classifier, language: "en") }
        ideas.pictureChanged(to: newer)
        let second = Task { await ideas.guess(newer, using: classifier, language: "en") }
        await classifier.finish(older, with: ["cat"])
        await first.value
        #expect(ideas.names.isEmpty, "a newer photo is on the tile")
        await classifier.finish(newer, with: ["dog"])
        await second.value
        #expect(ideas.names == ["dog"])
    }

    /// A symbol or drawing (a picture of its own), an emoji or "Remove photo" (no picture): no ideas, and
    /// none arriving later for the photo they replaced.
    @Test(arguments: [Data([9]), nil])
    func anythingButAPhotoClearsTheIdeas(replacement: Data?) async {
        let ideas = PhotoNameIdeas()
        let classifier = HeldClassifier()
        ideas.pictureChanged(to: older)
        await classifier.finish(older, with: ["dog"])
        await ideas.guess(older, using: classifier, language: "en")
        #expect(ideas.names == ["dog"])
        ideas.pictureChanged(to: replacement)
        #expect(ideas.names.isEmpty)

        ideas.pictureChanged(to: newer)
        let late = Task { await ideas.guess(newer, using: classifier, language: "en") }
        ideas.pictureChanged(to: replacement)
        await classifier.finish(newer, with: ["cat"])
        await late.value
        #expect(ideas.names.isEmpty)
    }

    @Test func noIdeasInOtherLanguages() async {
        let ideas = PhotoNameIdeas()
        ideas.pictureChanged(to: older)
        await ideas.guess(older, using: FakeClassifier(guesses: [guess("dog", 0.9)]), language: "fr")
        #expect(ideas.names.isEmpty)
    }

    @Test func tappingAnIdeaKeepsTheParentsOwnWords() async {
        let ideas = PhotoNameIdeas()
        ideas.pictureChanged(to: older)
        await ideas.guess(older, using: FakeClassifier(guesses: [guess("dog", 0.9), guess("puppy", 0.8)]), language: "en")
        #expect(ideas.phrase(using: "dog", instead: "") == "dog")
        #expect(ideas.phrase(using: "dog", instead: "  \n") == "dog")
        #expect(ideas.phrase(using: "puppy", instead: "dog") == "puppy", "an earlier guess is replaced")
        #expect(ideas.phrase(using: "puppy", instead: " dog ") == "puppy")
        #expect(ideas.phrase(using: "puppy", instead: "Our dog Rex!") == "Our dog Rex!")
    }
}
