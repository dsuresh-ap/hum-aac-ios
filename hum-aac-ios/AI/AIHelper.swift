// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import HumConfig
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The parent-only AI helper (off by default). It only ever makes a *proposal*:
/// model output → `ProposalChecker` (code-level GLP rules) → the normal import preview → parent taps Apply.
///
/// Only text is sent: the parent's request plus the labels, phrases and function tags of the boards.
/// Photos and recordings are never sent. On-device mode keeps everything on the device; Private Cloud
/// Compute sends the text to Apple's PCC, which doesn't store it.
enum AIHelper {
    enum Mode: String, CaseIterable, Sendable { case onDevice, privateCloud }

    enum Availability: Equatable {
        case available
        /// Plain-language reason, shown to the parent. The rest of Hum works normally.
        case unavailable(String)
    }

    enum Task: Sendable {
        /// "My child loves trains and says 'all aboard!' when she wants to go."
        case describe(String)
        /// Phrases the child says, plus where/when they say them.
        case capture(phrases: [String], context: String)
    }

    struct Proposal {
        var tiles: [ProposedTile]
        var notes: [String]
        var parentPhrases: [String]
    }

    static let instructions = """
        You help a parent set up Hum, an AAC app for an autistic child who is a Gestalt Language \
        Processor (GLP). GLP children communicate with whole memorized phrases ("gestalts"), often from \
        shows, songs or things adults say. Rules you must follow:
        1. One tile = one whole gestalt. Never split a phrase into several tiles or into single words. \
        Keep the child's exact wording, including scripts like "to infinity and beyond!".
        2. spokenText is the whole phrase. label is 1 to 4 short words shown on the tile.
        3. Never suggest praise, rewards or compliance phrases (no "good job", "quiet hands", "look at me").
        4. Protest and regulation phrases ("no thank you", "stop!", "I need a break") are important \
        communication, not problems.
        5. function is one of: protest, request, connection, comment, regulation, other.
        6. Only suggest new tiles. Never suggest removing or moving tiles.
        7. Suggest at most 12 tiles. Use boardName only when a new sub-board clearly helps (e.g. "Trains").
        """

    static func availability(mode: Mode) -> Availability {
        #if canImport(FoundationModels)
        if mode == .privateCloud {
            #if compiler(>=6.4)
            if #available(iOS 27.0, macOS 27.0, *) {
                switch PrivateCloudComputeLanguageModel().availability {
                case .available: return .available
                case .unavailable(.deviceNotEligible): return .unavailable("This device can't use Private Cloud Compute.")
                case .unavailable: return .unavailable("Private Cloud Compute isn't ready yet. Check that Apple Intelligence is on and you're online.")
                }
            }
            #endif
            return .unavailable("Private Cloud Compute needs iOS, iPadOS or macOS 27.")
        }
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.deviceNotEligible): return .unavailable("This device doesn't support Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled): return .unavailable("Turn on Apple Intelligence in Settings to use the helper.")
            case .unavailable(.modelNotReady): return .unavailable("Apple Intelligence is still getting ready (the model may be downloading). Try again later.")
            case .unavailable: return .unavailable("Apple Intelligence isn't available right now.")
            }
        }
        #endif
        return .unavailable("The AI helper needs iOS, iPadOS or macOS 26 or later with Apple Intelligence.")
    }

    /// True when at least one mode can run on this device (the helper is hidden otherwise).
    static var isSupportedOnThisDevice: Bool {
        if case .available = availability(mode: .onDevice) { return true }
        if case .available = availability(mode: .privateCloud) { return true }
        return false
    }

    /// Asks the model, then applies the code-level GLP checks.
    @MainActor
    static func propose(_ task: Task, mode: Mode, existing: HumDocument) async throws -> Proposal {
        let parentPhrases: [String]
        let request: String
        switch task {
        case .describe(let text):
            parentPhrases = quotedPhrases(in: text)
            request = "The parent says: \(text)\nSuggest whole-gestalt tiles for this child."
        case .capture(let phrases, let context):
            parentPhrases = phrases
            request = """
                The child says these phrases (each is one whole gestalt; keep each one whole and exact):
                \(phrases.map { "- \($0)" }.joined(separator: "\n"))
                Context from the parent: \(context.isEmpty ? "none" : context)
                Make one tile per phrase with a short label and a function tag.
                """
        }
        let prompt = request + "\n\nTiles already on the boards (don't repeat them):\n" + boardsSummary(existing)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let raw = try await generate(prompt: prompt, mode: mode)
            let proposed = raw.map {
                ProposedTile(label: $0.label, spokenText: $0.spokenText,
                             function: TileFunction(rawValue: $0.function.lowercased()),
                             boardName: $0.boardName?.isEmpty == true ? nil : $0.boardName)
            }
            let checked = ProposalChecker.check(proposed, parentPhrases: parentPhrases, existing: existing)
            return Proposal(tiles: checked.tiles, notes: checked.notes, parentPhrases: parentPhrases)
        }
        #endif
        throw AIError.unavailable
    }

    /// Text-only summary of the boards for the prompt (no photos, no recordings).
    static func boardsSummary(_ doc: HumDocument, limit: Int = 150) -> String {
        var lines: [String] = []
        var count = 0
        for board in doc.boards {
            lines.append("Board \"\(board.name)\"\(board.isHome ? " (Home)" : ""):")
            for tile in board.tiles where count < limit {
                count += 1
                lines.append("- \(tile.label) = \"\(tile.spokenText)\"\(tile.function.map { " [\($0.rawValue)]" } ?? "")")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Phrases the parent put in quotes ("all aboard!") are gestalts that must stay whole.
    static func quotedPhrases(in text: String) -> [String] {
        let pattern = #"[\"“”‘’']([^\"“”‘’']{2,200})[\"“”‘’']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) }
        }.filter { $0.contains(" ") || $0.count > 3 }
    }

    enum AIError: LocalizedError {
        case unavailable
        var errorDescription: String? { "The AI helper isn't available on this device right now." }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct AITileSuggestion {
    @Guide(description: "1 to 4 short words shown on the tile")
    var label: String
    @Guide(description: "The whole phrase the tile says, exactly as the child says it. One whole gestalt, never split.")
    var spokenText: String
    @Guide(description: "What the phrase is for", .anyOf(["protest", "request", "connection", "comment", "regulation", "other"]))
    var function: String
    @Guide(description: "Optional sub-board name like Trains or Food. Empty for the current board.")
    var boardName: String?
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct AITileProposal {
    @Guide(description: "New tiles to suggest", .maximumCount(12))
    var tiles: [AITileSuggestion]
}

extension AIHelper {
    @available(iOS 26.0, macOS 26.0, *)
    @MainActor
    static func generate(prompt: String, mode: Mode) async throws -> [AITileSuggestion] {
        let session: LanguageModelSession
        #if compiler(>=6.4)
        if mode == .privateCloud, #available(iOS 27.0, macOS 27.0, *) {
            session = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
        } else {
            session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        }
        #else
        session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        #endif
        let response = try await session.respond(to: prompt, generating: AITileProposal.self)
        return response.content.tiles
    }
}
#endif
