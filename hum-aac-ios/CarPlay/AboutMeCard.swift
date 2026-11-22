// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// CarPlay's "About me" tab: a short card for a police officer, a tow truck driver or a paramedic to
/// read, like the "Blue Envelope" some US states give autistic drivers. "Say this" reads it out.
///
/// It belongs to this iPhone (DeviceSettings): never synced or exported, since it can hold a name and
/// a phone number.
struct AboutMeCard: Codable, Equatable, Sendable {
    var name = ""
    /// What the card says, one line each, in the driver's own words.
    var lines: [String] = []
    var contactName = ""
    var contactPhone = ""

    /// CarPlay shows at most 10 items on an information screen: the name, these lines and the contact.
    static let maximumLines = 7

    /// The lines with something in them, at most `maximumLines`.
    var shownLines: [String] {
        Array(lines.map(Self.trimmed).filter { !$0.isEmpty }.prefix(Self.maximumLines))
    }

    var hasContact: Bool { !Self.trimmed(contactName).isEmpty || !Self.trimmed(contactPhone).isEmpty }

    /// Nothing to show: the car has no About me tab.
    var isEmpty: Bool { Self.trimmed(name).isEmpty && shownLines.isEmpty && !hasContact }

    /// The contact as the card shows it, e.g. "Sam · 555 0100".
    var contactText: String {
        [contactName, contactPhone].map(Self.trimmed).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// What "Say this" says: the name, the lines, then the contact. The phone number's digits are
    /// spaced out, so the voice reads them one by one instead of as one big number.
    var spokenText: String {
        var parts: [String] = []
        let name = Self.trimmed(name)
        if !name.isEmpty {
            parts.append(String(localized: "My name is \(name).", comment: "CarPlay About me card, read out. The argument is the driver's name."))
        }
        parts += shownLines.map(Self.sentence)
        let who = Self.trimmed(contactName)
        let digits = Self.spokenDigits(contactPhone)
        switch (who.isEmpty, digits.isEmpty) {
        case (false, false):
            parts.append(String(localized: "My emergency contact is \(who). Their number is \(digits).",
                                comment: "CarPlay About me card, read out. A name, then a phone number read digit by digit."))
        case (false, true):
            parts.append(String(localized: "My emergency contact is \(who).", comment: "CarPlay About me card, read out. A name."))
        case (true, false):
            parts.append(String(localized: "My emergency contact's number is \(digits).",
                                comment: "CarPlay About me card, read out. A phone number read digit by digit."))
        case (true, true):
            break
        }
        return parts.joined(separator: " ")
    }

    /// Lines a parent can start from. They're the driver's words, so they say "I".
    static var suggestions: [String] {
        [
            String(localized: "I'm autistic.", comment: "Suggested line for the CarPlay About me card."),
            String(localized: "I don't speak. I use this app to talk.", comment: "Suggested line for the CarPlay About me card."),
            String(localized: "I understand you. I answer by tapping this screen.", comment: "Suggested line for the CarPlay About me card."),
            String(localized: "Please ask me yes or no questions.", comment: "Suggested line for the CarPlay About me card."),
            String(localized: "Please give me time to answer.", comment: "Suggested line for the CarPlay About me card."),
            String(localized: "Loud voices and flashing lights make it hard for me to answer.", comment: "Suggested line for the CarPlay About me card."),
            String(localized: "Please write things down for me.", comment: "Suggested line for the CarPlay About me card."),
        ]
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A line ends with a full stop when read out, so the voice pauses between lines.
    private static func sentence(_ line: String) -> String {
        guard let last = line.last, !".!?。！？".contains(last) else { return line }
        return line + "."
    }

    private static func spokenDigits(_ phone: String) -> String {
        phone.filter(\.isNumber).map(String.init).joined(separator: " ")
    }
}
