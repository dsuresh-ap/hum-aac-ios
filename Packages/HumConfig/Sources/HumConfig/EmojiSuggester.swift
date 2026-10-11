// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Picks a placeholder emoji for a tile from its words ("Let's have juice!" → 🧃), and holds the
/// small, AAC-focused emoji set the parent picker shows. Works offline, with no model and no network.
///
/// It's only a placeholder until the parent adds a real photo, so a good guess is enough.
public enum EmojiSuggester {
    public struct Entry: Sendable, Hashable {
        public let emoji: String
        public let keywords: [String]
    }

    public struct Category: Sendable, Hashable, Identifiable {
        public let name: String
        public let entries: [Entry]
        public var id: String { name }
    }

    /// Best guesses for a tile, best first. Words in the label count more than words in the phrase.
    public static func suggestions(label: String, spokenText: String, limit: Int = 6) -> [String] {
        var scores: [String: Int] = [:]
        var order: [String] = []
        func add(_ emoji: String, _ points: Int) {
            if scores[emoji] == nil { order.append(emoji) }
            scores[emoji, default: 0] += points
        }
        for (text, weight) in [(label, 3), (spokenText, 2)] {
            let words = tokens(text)
            // Two-word keywords first ("ice cream", "all done"), then single words.
            for pair in zip(words, words.dropFirst()) {
                for emoji in index["\(pair.0) \(pair.1)"] ?? [] { add(emoji, weight * 2) }
            }
            for word in words {
                for form in forms(of: word) {
                    if let hits = index[form] {
                        for emoji in hits { add(emoji, weight) }
                        break
                    }
                }
            }
        }
        return order.enumerated()
            .sorted { (scores[$0.element]!, -$0.offset) > (scores[$1.element]!, -$1.offset) }
            .prefix(limit)
            .map(\.element)
    }

    /// The single best guess, or nil when no word matches.
    public static func suggestion(label: String, spokenText: String) -> String? {
        suggestions(label: label, spokenText: spokenText, limit: 1).first
    }

    /// Entries whose keywords start with the search text (for the picker's search field).
    public static func search(_ text: String) -> [String] {
        let query = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var seen = Set<String>()
        return categories.flatMap(\.entries)
            .filter { entry in entry.keywords.contains { $0.hasPrefix(query) } }
            .map(\.emoji)
            .filter { seen.insert($0).inserted }
    }

    /// True when `text` is exactly one emoji (what a tile's `symbol` should be).
    public static func isSingleEmoji(_ text: String) -> Bool {
        guard text.count == 1, let character = text.first else { return false }
        return character.unicodeScalars.contains { $0.properties.isEmojiPresentation }
            || (character.unicodeScalars.first?.properties.isEmoji == true && character.unicodeScalars.count > 1)
    }

    // MARK: Matching

    /// Lowercased words without punctuation. "Let's" → "let's", "juice!" → "juice".
    public static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    /// The word, then simple singular / base forms ("trains" → "train", "swinging" → "swing").
    static func forms(of word: String) -> [String] {
        var result = [word]
        if word.hasSuffix("ies"), word.count > 4 { result.append(String(word.dropLast(3)) + "y") }
        if word.hasSuffix("es"), word.count > 3 { result.append(String(word.dropLast(2))) }
        if word.hasSuffix("s"), word.count > 3 { result.append(String(word.dropLast())) }
        if word.hasSuffix("ing"), word.count > 5 {
            let stem = String(word.dropLast(3))
            result.append(stem)
            result.append(stem + "e")
            if let last = stem.last, stem.dropLast().last == last { result.append(String(stem.dropLast())) }
        }
        return result
    }

    static let stopWords: Set<String> = [
        "a", "an", "the", "i", "me", "my", "you", "your", "it", "is", "are", "to", "of", "and", "or", "in",
        "on", "at", "for", "with", "let's", "lets", "want", "wanna", "some", "more", "please", "this", "that",
        "do", "can", "have", "let", "we", "us", "be", "go's",
    ]

    /// keyword → emoji, built once from `categories`.
    static let index: [String: [String]] = {
        var map: [String: [String]] = [:]
        for entry in categories.flatMap(\.entries) {
            for keyword in entry.keywords where !(map[keyword]?.contains(entry.emoji) ?? false) {
                map[keyword, default: []].append(entry.emoji)
            }
        }
        return map
    }()

    // MARK: The emoji set

    private static func e(_ emoji: String, _ keywords: String) -> Entry {
        Entry(emoji: emoji, keywords: keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    /// Picked for everyday AAC: requests, protest and regulation, feelings, food, play, places.
    public static let categories: [Category] = [
        Category(name: "Feelings & me", entries: [
            e("😊", "happy, glad, smile, fun, yay, like"),
            e("😢", "sad, cry, crying, upset"),
            e("😠", "mad, angry, cross, grumpy"),
            e("😨", "scared, afraid, scary, frightened, worried"),
            e("😮", "uh oh, oh, surprise, wow, whoa, oops"),
            e("😴", "tired, sleepy, sleep, nap, bed, bedtime"),
            e("🤒", "sick, ill, hurts, hurt, ouch, pain"),
            e("🤢", "yucky, yuck, gross, icky"),
            e("😋", "yummy, tasty, delicious"),
            e("😂", "funny, silly, laugh, joke, haha"),
            e("🥰", "love, hug, cuddle, snuggle"),
            e("🤗", "hi, hello, hey, hug"),
            e("👋", "bye, goodbye, bye-bye, see you, wave"),
            e("😎", "cool, awesome"),
            e("🤔", "think, wonder, hmm, why, what"),
            e("😕", "confused, don't know, dunno"),
            e("🥱", "bored, boring"),
            e("😤", "frustrated, annoyed"),
            e("🙂", "okay, ok, fine, alright"),
            e("🫶", "together, us, family"),
        ]),
        Category(name: "Yes, no & help", entries: [
            e("✋", "stop, wait, no thank you, enough"),
            e("🙅", "no, nope, don't, not"),
            e("👍", "yes, yeah, yep, good, sure, okay"),
            e("✅", "all done, done, finished, finish, the end"),
            e("🆘", "help, help me, emergency"),
            e("🤝", "help, share, turn, my turn, your turn"),
            e("⏸️", "break, pause, rest, need a break"),
            e("🔇", "too loud, loud, quiet, noise, noisy"),
            e("🔁", "again, more, another, repeat, one more"),
            e("👉", "this, that, there, look, point"),
            e("👀", "look, see, watch, look at"),
            e("❓", "question, ask, what's that"),
            e("🙏", "please, thank you, thanks"),
            e("🚫", "not, never, forbidden"),
            e("⏰", "time, later, soon, now, wait"),
        ]),
        Category(name: "Food & drink", entries: [
            e("🍎", "apple, apples, fruit"),
            e("🍌", "banana, bananas"),
            e("🍇", "grapes, grape"),
            e("🍓", "strawberry, strawberries, berry, berries"),
            e("🍊", "orange, oranges, clementine"),
            e("🍉", "watermelon, melon"),
            e("🥕", "carrot, carrots, vegetable, veggies"),
            e("🥦", "broccoli"),
            e("🌽", "corn"),
            e("🥔", "potato"),
            e("🍟", "fries, french fries, chips"),
            e("🍕", "pizza"),
            e("🍔", "burger, hamburger"),
            e("🌭", "hot dog, hotdog, sausage"),
            e("🍝", "pasta, spaghetti, noodles, mac"),
            e("🍚", "rice"),
            e("🥪", "sandwich, lunch"),
            e("🍞", "bread, toast"),
            e("🧀", "cheese"),
            e("🥚", "egg, eggs"),
            e("🍗", "chicken, nuggets"),
            e("🥣", "cereal, breakfast, bowl, oatmeal"),
            e("🥞", "pancakes, pancake, waffle, waffles"),
            e("🍘", "crackers, cracker, snack, snacks"),
            e("🍪", "cookie, cookies, biscuit, treat"),
            e("🍰", "cake, birthday cake"),
            e("🍦", "ice cream, icecream"),
            e("🍫", "chocolate, candy"),
            e("🍿", "popcorn"),
            e("🥨", "pretzel, pretzels"),
            e("🍯", "honey"),
            e("🥛", "milk"),
            e("🧃", "juice, juice box"),
            e("💧", "water"),
            e("🥤", "drink, thirsty, soda, cup"),
            e("🍽️", "eat, hungry, food, dinner, meal, plate"),
            e("🍼", "bottle, baby"),
        ]),
        Category(name: "Play & things", entries: [
            e("⚽", "ball, soccer, kick"),
            e("🏀", "basketball"),
            e("🧸", "teddy, bear, toy, toys, stuffie"),
            e("🧱", "blocks, block, lego, build"),
            e("🧩", "puzzle, puzzles"),
            e("🎨", "paint, painting, art, color, colour"),
            e("🖍️", "crayon, crayons, draw, drawing"),
            e("📚", "book, books, read, story"),
            e("🎵", "music, song, sing, singing"),
            e("💃", "dance, dancing"),
            e("📺", "tv, television, show, cartoon, movie, watch"),
            e("📱", "phone, ipad, tablet, video, videos"),
            e("🎮", "game, games, video game"),
            e("🫧", "bubbles, bubble"),
            e("🎈", "balloon, balloons, party"),
            e("🎁", "present, gift, surprise"),
            e("🚂", "train, trains, choo choo, all aboard"),
            e("🚗", "car, cars, drive, ride"),
            e("🚌", "bus, school bus"),
            e("✈️", "airplane, plane, fly, flying"),
            e("🚀", "rocket, space, infinity, beyond, blast off"),
            e("🚲", "bike, bicycle"),
            e("🛝", "slide, playground"),
            e("🤸", "jump, jumping, trampoline, tumble"),
            e("🔄", "spin, swing, round"),
            e("🙈", "hide, hide and seek, peekaboo, boo"),
            e("🦸", "superhero, hero"),
            e("🪁", "kite"),
            e("🎉", "yay, hooray, party, celebrate"),
        ]),
        Category(name: "Places & outside", entries: [
            e("🏠", "home, house"),
            e("🏫", "school, class, teacher"),
            e("🌳", "outside, park, tree, trees, garden"),
            e("🏖️", "beach, sand"),
            e("🏊", "swim, swimming, pool"),
            e("🛁", "bath, bathtub"),
            e("🚽", "potty, toilet, bathroom, pee, poop"),
            e("🛏️", "bed, bedroom"),
            e("🛒", "shop, store, shopping, grocery"),
            e("🏥", "doctor, hospital"),
            e("🚪", "door, out, leave, get out, let's go, go"),
            e("🚶", "walk, walking"),
            e("🏃", "run, running, chase, fast"),
            e("☀️", "sun, sunny, hot, day"),
            e("🌧️", "rain, raining, rainy"),
            e("❄️", "snow, cold, winter"),
            e("🌙", "night, moon, goodnight"),
            e("⭐", "star, stars"),
            e("🌈", "rainbow"),
            e("🌸", "flower, flowers"),
        ]),
        Category(name: "Animals", entries: [
            e("🐶", "dog, puppy, doggy"),
            e("🐱", "cat, kitty, kitten"),
            e("🐟", "fish"),
            e("🐦", "bird, birds"),
            e("🦆", "duck, ducks, quack"),
            e("🐸", "frog"),
            e("🐄", "cow, moo"),
            e("🐷", "pig, oink"),
            e("🐴", "horse"),
            e("🐑", "sheep, baa"),
            e("🐔", "chicken, hen"),
            e("🐰", "bunny, rabbit"),
            e("🦁", "lion, roar"),
            e("🐯", "tiger"),
            e("🐘", "elephant"),
            e("🐵", "monkey"),
            e("🦒", "giraffe"),
            e("🦖", "dinosaur, dino, t-rex"),
            e("🦈", "shark"),
            e("🐻", "bear"),
            e("🦋", "butterfly"),
            e("🐛", "bug, bugs, caterpillar"),
            e("🐝", "bee, bees"),
        ]),
        Category(name: "Body & care", entries: [
            e("🪥", "teeth, brush teeth, toothbrush"),
            e("🧼", "wash, wash hands, soap, clean"),
            e("👕", "clothes, shirt, dress, get dressed"),
            e("👟", "shoes, shoe, socks"),
            e("🧥", "coat, jacket"),
            e("🩹", "boo boo, owie, bandaid, band-aid"),
            e("💊", "medicine"),
            e("💇", "hair, haircut, comb"),
            e("👂", "ears, ear, listen, hear"),
            e("👃", "nose"),
            e("👄", "mouth, kiss"),
            e("🖐️", "hand, hands, high five"),
            e("🫂", "hug, hugs, squeeze, hold"),
            e("🎧", "headphones, quiet, ear defenders"),
            e("🌬️", "breathe, breath, calm, calm down"),
        ]),
        Category(name: "People", entries: [
            e("👩", "mom, mommy, mama, mum, mummy"),
            e("👨", "dad, daddy, papa"),
            e("👵", "grandma, nana, granny, gran"),
            e("👴", "grandpa, papa, grandad, pop"),
            e("👶", "baby, sister, brother"),
            e("🧒", "friend, friends, kid, kids"),
            e("👧", "girl, sister"),
            e("👦", "boy, brother"),
            e("🧑‍🏫", "teacher"),
            e("👥", "everyone, people, we"),
        ]),
    ]
}
