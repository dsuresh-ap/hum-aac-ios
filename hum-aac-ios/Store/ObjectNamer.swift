// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import Vision

/// One guess about what's in a photo: Vision's English name for it ("food_bowl") and how sure it is (0...1).
nonisolated struct ObjectGuess: Equatable, Sendable {
    let identifier: String
    let confidence: Double
}

/// Looks at a photo and guesses what's in it. Tests use a fake.
nonisolated protocol ObjectClassifying: Sendable {
    /// Guesses, most confident first. Empty when nothing could be read.
    func classify(_ imageData: Data) async -> [ObjectGuess]
}

/// Apple's Vision image classifier. It runs on this device only: the photo never leaves it.
nonisolated struct VisionObjectClassifier: ObjectClassifying {
    func classify(_ imageData: Data) async -> [ObjectGuess] {
        // Off the main thread: a big photo can take a moment.
        await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            do {
                try VNImageRequestHandler(data: imageData).perform([request])
            } catch {
                return []
            }
            return (request.results ?? []).map { ObjectGuess(identifier: $0.identifier, confidence: Double($0.confidence)) }
        }.value
    }
}

/// The "Looks like:" names for the photo in the tile editor. Only the newest photo's names show: a slow
/// guess for a photo that was replaced, removed or swapped for a symbol is dropped.
@MainActor
@Observable
final class PhotoNameIdeas {
    private(set) var names: [String] = []
    /// The picture the names are for (or being guessed for).
    @ObservationIgnored private var picture: Data?

    /// Every picture change. A symbol, a drawing or no picture has no ideas.
    func pictureChanged(to data: Data?) {
        picture = data
        names = []
    }

    /// Guesses what's in `data`, the photo just set with `pictureChanged(to:)`, on this device.
    func guess(_ data: Data, using classifier: any ObjectClassifying,
               language: String? = Bundle.main.preferredLocalizations.first) async {
        let ideas = await ObjectNamer.names(for: data, using: classifier, language: language)
        // The parent may have picked another picture meanwhile.
        if picture == data { names = ideas }
    }

    /// The phrase after the parent taps `name`: the name while the phrase is empty or still an earlier
    /// guess. The parent's own words are kept.
    func phrase(using name: String, instead phrase: String) -> String {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || names.contains(trimmed) ? name : phrase
    }
}

/// Turns Vision's guesses into a few plain words a parent can tap to name a tile.
nonisolated enum ObjectNamer {
    /// Guesses below this are too often wrong to show.
    static let minimumConfidence = 0.2

    /// Vision's names are English. In other languages Hum shows no ideas for now.
    /// TODO: a word table like EmojiKeywords.xcstrings would let translators add the other languages.
    static func isAvailable(language: String? = Bundle.main.preferredLocalizations.first) -> Bool {
        language?.hasPrefix("en") ?? true
    }

    /// The names to offer for a photo: none when Hum isn't shown in English.
    static func names(for imageData: Data, using classifier: any ObjectClassifying,
                      language: String? = Bundle.main.preferredLocalizations.first) async -> [String] {
        guard isAvailable(language: language) else { return [] }
        return suggestions(from: await classifier.classify(imageData))
    }

    /// Up to `limit` words, most likely first, without broad groups ("animal") or repeats.
    static func suggestions(from guesses: [ObjectGuess], limit: Int = 3) -> [String] {
        // Most confident first; equal guesses keep Vision's order.
        let ranked = guesses.enumerated().sorted { a, b in
            a.element.confidence != b.element.confidence ? a.element.confidence > b.element.confidence : a.offset < b.offset
        }.map(\.element)
        var words: [String] = []
        for guess in ranked {
            guard words.count < limit else { break }
            guard guess.confidence >= minimumConfidence, !broad.contains(guess.identifier) else { continue }
            let word = readable(guess.identifier)
            if !word.isEmpty, !words.contains(word) { words.append(word) }
        }
        return words
    }

    /// "food_bowl" → "food bowl", "chair_other" → "chair", "balloon_hotair" → "hot air balloon".
    static func readable(_ identifier: String) -> String {
        let id = identifier.lowercased()
        if let word = renamed[id] { return word }
        var name = id
        if name.hasSuffix("_other") { name.removeLast("_other".count) }
        return name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Names whose plain form isn't just "underscores to spaces".
    static let renamed: [String: String] = [
        "adult_cat": "cat", "alligator_crocodile": "crocodile", "balloon_hotair": "hot air balloon",
        "basket_container": "basket", "bathroom_room": "bathroom", "cake_regular": "cake", "coyote_wolf": "wolf",
        "crane_construction": "crane", "cricket_sport": "cricket", "drone_machine": "drone", "engine_vehicle": "engine",
        "fencing_sport": "fencing", "house_single": "house", "interior_shop": "shop", "iron_clothing": "iron",
        "jack_o_lantern": "jack-o'-lantern", "jockey_horse": "jockey", "kitchen_room": "kitchen", "oranges": "orange",
        "organ_instrument": "organ", "pepper_veggie": "pepper", "play_card": "playing cards", "pot_cooking": "pot",
        "raw_glass": "glass", "slide_toy": "slide", "speakers_music": "speakers", "squash_sport": "squash",
        "steamer_cookware": "steamer", "straw_drinking": "straw", "straw_hay": "hay", "submarine_water": "submarine",
        "sunset_sunrise": "sunset", "swing_playground": "swing", "tea_drink": "tea", "track_rail": "train track",
        "train_real": "train", "train_toy": "toy train", "wood_natural": "wood",
    ]

    /// Groups too broad to name one thing on a tile, and backgrounds ("blue sky" behind a zebra). Vision gives
    /// groups as high a score as the thing itself (a dog photo is "animal" as surely as "dog"), so they would
    /// push the useful word out.
    static let broad: Set<String> = [
        "adult", "agriculture", "aircraft", "animal", "appliance", "arachnid", "art", "arthropods", "athletics",
        "automobile", "baked_goods", "ballgames", "blue_sky", "canine", "celebration", "celestial_body", "celestial_body_other",
        "cephalopod", "cetacean", "clothing", "consumer_electronics", "container", "conveyance", "cookware",
        "daytime", "decoration", "document", "domicile", "entertainer", "feline", "foliage", "food", "footwear",
        "frozen_dessert", "furniture", "games", "gastropod", "headgear", "housewares", "illustrations",
        "interior_room", "land", "liquid", "machine", "mammal", "marsupial", "material", "media", "mollusk",
        "music", "musical_instrument", "night_sky", "office_supplies", "optical_equipment", "outdoor", "people", "raptor",
        "recreation", "reptile", "road_safety_equipment", "rodent", "seasonings", "shellfish_prepared",
        "ski_equipment", "smoking_item", "sport", "sports_equipment", "string_instrument", "structure",
        "tableware", "teen", "textile", "timepiece", "tool", "underwater", "ungulates", "utensil", "vegetation", "vehicle",
        "water_body", "watercraft", "watersport", "waterways", "winter_sport", "wood_processed",
    ]
}
