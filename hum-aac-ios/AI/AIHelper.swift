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

    /// Private Cloud Compute daily allowance, for the parent-facing status line.
    struct QuotaInfo: Equatable {
        enum Level: Equatable { case fine, approaching, reached }
        var level: Level
        var resetDate: Date?
        var canShowOptions: Bool
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

    /// What the model returned, already mapped to `ProposedTile`.
    struct Generation: Sendable {
        var tiles: [ProposedTile]
        /// Private Cloud Compute couldn't be reached, so the on-device model answered.
        var usedOnDeviceFallback = false
    }

    /// Runs one prompt. Tests pass a fake; the app uses Foundation Models.
    typealias Generator = @MainActor (_ prompt: String, _ mode: Mode) async throws -> Generation

    /// The prompt for a task: the parent's request plus the existing tiles (so the model doesn't repeat
    /// them). `short` lists fewer tiles, for when the full prompt is too long for the on-device model.
    static func prompts(for task: Task, existing: HumDocument) -> (parentPhrases: [String], full: String, short: String) {
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
        return (parentPhrases,
                request + "\n\nTiles already on the boards (don't repeat them):\n" + boardsSummary(existing),
                request + "\n\nSome tiles already on the boards (don't repeat them):\n" + boardsSummary(existing, limit: 30))
    }

    /// Asks the model, then applies the code-level GLP checks.
    @MainActor
    static func propose(_ task: Task, mode: Mode, existing: HumDocument, generator: Generator? = nil) async throws -> Proposal {
        let (parentPhrases, prompt, shortPrompt) = prompts(for: task, existing: existing)
        let generate = generator ?? foundationModelsGenerator
        let result: Generation
        do {
            result = try await generate(prompt, mode)
        } catch AIError.contextTooLong {
            // Big setups can overflow the on-device model's context: retry with fewer existing tiles.
            result = try await generate(shortPrompt, mode)
        }
        let checked = ProposalChecker.check(result.tiles, parentPhrases: parentPhrases, existing: existing)
        var notes = checked.notes
        if result.usedOnDeviceFallback {
            notes.insert("Private Cloud Compute couldn't be reached, so these suggestions came from the model on this device.", at: 0)
        }
        return Proposal(tiles: checked.tiles, notes: notes, parentPhrases: parentPhrases)
    }

    /// The real model (Foundation Models), or `unavailable` on systems without it.
    @MainActor
    static func foundationModelsGenerator(_ prompt: String, _ mode: Mode) async throws -> Generation {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let (raw, fallback) = try await generate(prompt: prompt, mode: mode)
            return Generation(tiles: raw.map(\.proposedTile), usedOnDeviceFallback: fallback)
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

    enum AIError: LocalizedError, Equatable {
        case unavailable
        case stillDownloading
        case contextTooLong
        case cantHelpWithThat
        case unsupportedLanguage
        case busy
        case quotaReached(resetDate: Date?)
        case cloudUnreachable
        case other

        var errorDescription: String? {
            switch self {
            case .unavailable: return "The AI helper isn't available on this device right now."
            case .stillDownloading: return "Apple Intelligence is still downloading on this device. Try again a little later."
            case .contextTooLong: return "That request is too long for the helper. Try a shorter description or fewer phrases at once."
            case .cantHelpWithThat: return "The helper couldn't make suggestions for that. Try describing what your child says or loves in a different way."
            case .unsupportedLanguage: return "The helper doesn't support this language yet."
            case .busy: return "The helper is busy. Try again in a moment."
            case .quotaReached(let date):
                if let date { return "You've used today's Private Cloud Compute requests. They refresh \(date.formatted(.relative(presentation: .named))). You can switch to \"On this device\" now." }
                return "You've used today's Private Cloud Compute requests. You can switch to \"On this device\" now."
            case .cloudUnreachable: return "Private Cloud Compute couldn't be reached, and the model on this device isn't available either. Check your connection and try again."
            case .other: return "Something went wrong. Please try again, or try a shorter request."
            }
        }
    }

    // MARK: Quota (Private Cloud Compute only)

    @MainActor
    static func quotaInfo() -> QuotaInfo? {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            let usage = PrivateCloudComputeLanguageModel().quotaUsage
            let level: QuotaInfo.Level
            switch usage.status {
            case .limitReached: level = .reached
            case .belowLimit(let info): level = info.isApproachingLimit ? .approaching : .fine
            @unknown default: level = .fine
            }
            return QuotaInfo(level: level, resetDate: usage.resetDate, canShowOptions: usage.limitIncreaseSuggestion != nil)
        }
        #endif
        return nil
    }

    /// Shows Apple's own options for more Private Cloud Compute requests (iCloud+). Hum sells nothing.
    @MainActor
    static func showQuotaOptions() {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            PrivateCloudComputeLanguageModel().quotaUsage.limitIncreaseSuggestion?.show()
        }
        #endif
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
    @Guide(description: "One emoji that pictures the phrase, like 🚂 for a train phrase")
    var emoji: String?

    var proposedTile: ProposedTile {
        ProposedTile(label: label, spokenText: spokenText,
                     function: TileFunction(rawValue: function.lowercased()),
                     boardName: boardName?.isEmpty == true ? nil : boardName,
                     symbol: emoji)
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct AITileProposal {
    @Guide(description: "New tiles to suggest", .maximumCount(12))
    var tiles: [AITileSuggestion]
}

extension AIHelper {
    /// Runs the request. Private Cloud Compute falls back to the on-device model when the network or the
    /// service is unavailable; a used-up daily quota is reported to the parent instead.
    @available(iOS 26.0, macOS 26.0, *)
    @MainActor
    static func generate(prompt: String, mode: Mode) async throws -> (tiles: [AITileSuggestion], usedOnDeviceFallback: Bool) {
        #if compiler(>=6.4)
        if mode == .privateCloud, #available(iOS 27.0, macOS 27.0, *) {
            do {
                let session = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
                let response = try await session.respond(to: prompt, generating: AITileProposal.self)
                return (response.content.tiles, false)
            } catch let error as PrivateCloudComputeLanguageModel.Error {
                switch error {
                case .quotaLimitReached(let info):
                    throw AIError.quotaReached(resetDate: info.resetDate)
                case .networkFailure, .serviceUnavailable:
                    guard case .available = availability(mode: .onDevice) else { throw AIError.cloudUnreachable }
                    return (try await onDevice(prompt), true)
                @unknown default:
                    // Any new cloud failure: still try on-device rather than leaving the parent stuck.
                    guard case .available = availability(mode: .onDevice) else { throw AIError.other }
                    return (try await onDevice(prompt), true)
                }
            }
        }
        #endif
        return (try await onDevice(prompt), false)
    }

    @available(iOS 26.0, macOS 26.0, *)
    @MainActor
    private static func onDevice(_ prompt: String) async throws -> [AITileSuggestion] {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        do {
            return try await session.respond(to: prompt, generating: AITileProposal.self).content.tiles
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: throw AIError.contextTooLong
            case .assetsUnavailable: throw AIError.stillDownloading
            case .guardrailViolation, .refusal, .decodingFailure: throw AIError.cantHelpWithThat
            case .unsupportedLanguageOrLocale: throw AIError.unsupportedLanguage
            case .rateLimited, .concurrentRequests: throw AIError.busy
            default: throw AIError.other
            }
        }
    }
}
#endif
