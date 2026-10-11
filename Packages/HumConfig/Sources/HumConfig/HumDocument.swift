// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

// The Codable types for `hum.json`. The JSON Schema in `schema/hum.schema.json` describes the same
// shape for humans and coding agents. If you change one, change the other (a test checks the examples).
//
// Every type keeps unknown fields in `extra` and writes them back out. A file made by a newer Hum (or
// by an agent that added its own notes) round-trips without losing anything.

/// A whole Hum setup: boards, tiles and (optionally) settings.
public struct HumDocument: Equatable, Sendable {
    /// The format version this build of HumConfig reads and writes.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    /// Optional human name for the setup, e.g. "Maya's boards".
    public var name: String?
    public var boards: [HumBoard]
    public var settings: HumSettings?
    public var extra: [String: JSONValue]

    public init(
        formatVersion: Int = HumDocument.currentFormatVersion,
        name: String? = nil,
        boards: [HumBoard] = [],
        settings: HumSettings? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.boards = boards
        self.settings = settings
        self.extra = extra
    }

    /// The board marked `isHome`, if any.
    public var homeBoard: HumBoard? { boards.first(where: \.isHome) }

    public func board(withID id: UUID) -> HumBoard? { boards.first { $0.id == id } }
}

/// One grid of tiles.
public struct HumBoard: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var rows: Int
    public var columns: Int
    public var isHome: Bool
    public var tiles: [HumTile]
    public var extra: [String: JSONValue]

    public init(
        id: UUID = UUID(), name: String, rows: Int, columns: Int, isHome: Bool = false,
        tiles: [HumTile] = [], extra: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.rows = rows
        self.columns = columns
        self.isHome = isHome
        self.tiles = tiles
        self.extra = extra
    }

    public func tile(atRow row: Int, column: Int) -> HumTile? {
        tiles.first { $0.row == row && $0.column == column }
    }
}

/// What a tile is for. Used for color and AI grouping. **Never** used to lock or hide a tile.
public enum TileFunction: String, Codable, CaseIterable, Sendable {
    case protest, request, connection, comment, regulation, other
}

/// One tile = one whole gestalt.
public struct HumTile: Equatable, Sendable, Identifiable {
    public var id: UUID
    /// Short text shown on the tile.
    public var label: String
    /// What the tile says, as one whole phrase. Never split into words.
    public var spokenText: String
    public var row: Int
    public var column: Int
    public var function: TileFunction?
    /// Background color as "#RRGGBB".
    public var color: String?
    /// Tapping this tile also opens this board.
    public var linkedBoardID: UUID?
    /// Hidden tiles keep their slot; the child sees an empty space.
    public var hidden: Bool
    /// Relative path inside the package, e.g. "media/snack.jpg".
    public var image: String?
    /// Relative path to a recorded phrase, e.g. "media/snack.m4a".
    public var audio: String?
    /// Placeholder emoji shown when there is no photo.
    public var symbol: String?
    public var extra: [String: JSONValue]

    public init(
        id: UUID = UUID(), label: String, spokenText: String, row: Int, column: Int,
        function: TileFunction? = nil, color: String? = nil, linkedBoardID: UUID? = nil,
        hidden: Bool = false, image: String? = nil, audio: String? = nil, symbol: String? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.label = label
        self.spokenText = spokenText
        self.row = row
        self.column = column
        self.function = function
        self.color = color
        self.linkedBoardID = linkedBoardID
        self.hidden = hidden
        self.image = image
        self.audio = audio
        self.symbol = symbol
        self.extra = extra
    }
}

/// Settings that can travel in a config file.
///
/// iCloud sync and AI are deliberately **not** here. Those send data off the device and must only be
/// turned on by a parent inside the app, never by importing a file.
public struct HumSettings: Equatable, Sendable {
    public enum LabelPosition: String, Codable, Sendable, CaseIterable { case top, bottom }
    public enum Appearance: String, Codable, Sendable, CaseIterable { case system, light, dark }
    public enum Retrigger: String, Codable, Sendable, CaseIterable { case restart, finish, overlap }
    public enum Activation: String, Codable, Sendable, CaseIterable { case touchDown, touchUp }

    public var voice: HumVoice?
    public var showLabels: Bool?
    public var labelPosition: LabelPosition?
    public var sentenceStrip: Bool?
    public var appearance: Appearance?
    public var retrigger: Retrigger?
    public var activation: Activation?
    public var extra: [String: JSONValue]

    public init(
        voice: HumVoice? = nil, showLabels: Bool? = nil, labelPosition: LabelPosition? = nil,
        sentenceStrip: Bool? = nil, appearance: Appearance? = nil, retrigger: Retrigger? = nil,
        activation: Activation? = nil, extra: [String: JSONValue] = [:]
    ) {
        self.voice = voice
        self.showLabels = showLabels
        self.labelPosition = labelPosition
        self.sentenceStrip = sentenceStrip
        self.appearance = appearance
        self.retrigger = retrigger
        self.activation = activation
        self.extra = extra
    }
}

public struct HumVoice: Equatable, Sendable {
    /// An `AVSpeechSynthesisVoice` identifier. Ignored if the voice is not installed on the device.
    public var identifier: String?
    /// 0.0 ... 1.0 (AVSpeechUtterance scale; 0.5 is normal).
    public var rate: Double?
    /// 0.5 ... 2.0 (1.0 is normal).
    public var pitch: Double?
    /// 0.0 ... 1.0
    public var volume: Double?
    public var extra: [String: JSONValue]

    public init(identifier: String? = nil, rate: Double? = nil, pitch: Double? = nil, volume: Double? = nil, extra: [String: JSONValue] = [:]) {
        self.identifier = identifier
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.extra = extra
    }
}

// MARK: - Codable (hand-written so unknown fields are kept)

extension HumDocument: Codable {
    static let knownKeys: Set<String> = ["formatVersion", "name", "boards", "settings"]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        formatVersion = try c.decode(Int.self, forKey: AnyKey("formatVersion"))
        name = try c.decodeIfPresent(String.self, forKey: AnyKey("name"))
        boards = try c.decodeIfPresent([HumBoard].self, forKey: AnyKey("boards")) ?? []
        settings = try c.decodeIfPresent(HumSettings.self, forKey: AnyKey("settings"))
        extra = try c.unknownFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encodeUnknownFields(extra)
        try c.encode(formatVersion, forKey: AnyKey("formatVersion"))
        try c.encodeIfPresent(name, forKey: AnyKey("name"))
        try c.encode(boards, forKey: AnyKey("boards"))
        try c.encodeIfPresent(settings, forKey: AnyKey("settings"))
    }
}

extension HumBoard: Codable {
    static let knownKeys: Set<String> = ["id", "name", "rows", "columns", "isHome", "tiles"]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = try c.decode(UUID.self, forKey: AnyKey("id"))
        name = try c.decode(String.self, forKey: AnyKey("name"))
        rows = try c.decode(Int.self, forKey: AnyKey("rows"))
        columns = try c.decode(Int.self, forKey: AnyKey("columns"))
        isHome = try c.decodeIfPresent(Bool.self, forKey: AnyKey("isHome")) ?? false
        tiles = try c.decodeIfPresent([HumTile].self, forKey: AnyKey("tiles")) ?? []
        extra = try c.unknownFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encodeUnknownFields(extra)
        try c.encode(id.uuidString.lowercased(), forKey: AnyKey("id"))
        try c.encode(name, forKey: AnyKey("name"))
        try c.encode(rows, forKey: AnyKey("rows"))
        try c.encode(columns, forKey: AnyKey("columns"))
        if isHome { try c.encode(true, forKey: AnyKey("isHome")) }
        try c.encode(tiles, forKey: AnyKey("tiles"))
    }
}

extension HumTile: Codable {
    static let knownKeys: Set<String> = [
        "id", "label", "spokenText", "row", "column", "function", "color", "linkedBoardID",
        "hidden", "image", "audio", "symbol",
    ]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = try c.decode(UUID.self, forKey: AnyKey("id"))
        spokenText = try c.decode(String.self, forKey: AnyKey("spokenText"))
        // A missing label falls back to the spoken text, like in the app.
        label = try c.decodeIfPresent(String.self, forKey: AnyKey("label")) ?? spokenText
        row = try c.decode(Int.self, forKey: AnyKey("row"))
        column = try c.decode(Int.self, forKey: AnyKey("column"))
        function = try c.decodeIfPresent(TileFunction.self, forKey: AnyKey("function"))
        color = try c.decodeIfPresent(String.self, forKey: AnyKey("color"))
        linkedBoardID = try c.decodeIfPresent(UUID.self, forKey: AnyKey("linkedBoardID"))
        hidden = try c.decodeIfPresent(Bool.self, forKey: AnyKey("hidden")) ?? false
        image = try c.decodeIfPresent(String.self, forKey: AnyKey("image"))
        audio = try c.decodeIfPresent(String.self, forKey: AnyKey("audio"))
        symbol = try c.decodeIfPresent(String.self, forKey: AnyKey("symbol"))
        extra = try c.unknownFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encodeUnknownFields(extra)
        try c.encode(id.uuidString.lowercased(), forKey: AnyKey("id"))
        try c.encode(label, forKey: AnyKey("label"))
        try c.encode(spokenText, forKey: AnyKey("spokenText"))
        try c.encode(row, forKey: AnyKey("row"))
        try c.encode(column, forKey: AnyKey("column"))
        try c.encodeIfPresent(function, forKey: AnyKey("function"))
        try c.encodeIfPresent(color, forKey: AnyKey("color"))
        try c.encodeIfPresent(linkedBoardID?.uuidString.lowercased(), forKey: AnyKey("linkedBoardID"))
        if hidden { try c.encode(true, forKey: AnyKey("hidden")) }
        try c.encodeIfPresent(image, forKey: AnyKey("image"))
        try c.encodeIfPresent(audio, forKey: AnyKey("audio"))
        try c.encodeIfPresent(symbol, forKey: AnyKey("symbol"))
    }
}

extension HumSettings: Codable {
    static let knownKeys: Set<String> = [
        "voice", "showLabels", "labelPosition", "sentenceStrip", "appearance", "retrigger", "activation",
    ]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        voice = try c.decodeIfPresent(HumVoice.self, forKey: AnyKey("voice"))
        showLabels = try c.decodeIfPresent(Bool.self, forKey: AnyKey("showLabels"))
        labelPosition = try c.decodeIfPresent(LabelPosition.self, forKey: AnyKey("labelPosition"))
        sentenceStrip = try c.decodeIfPresent(Bool.self, forKey: AnyKey("sentenceStrip"))
        appearance = try c.decodeIfPresent(Appearance.self, forKey: AnyKey("appearance"))
        retrigger = try c.decodeIfPresent(Retrigger.self, forKey: AnyKey("retrigger"))
        activation = try c.decodeIfPresent(Activation.self, forKey: AnyKey("activation"))
        extra = try c.unknownFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encodeUnknownFields(extra)
        try c.encodeIfPresent(voice, forKey: AnyKey("voice"))
        try c.encodeIfPresent(showLabels, forKey: AnyKey("showLabels"))
        try c.encodeIfPresent(labelPosition, forKey: AnyKey("labelPosition"))
        try c.encodeIfPresent(sentenceStrip, forKey: AnyKey("sentenceStrip"))
        try c.encodeIfPresent(appearance, forKey: AnyKey("appearance"))
        try c.encodeIfPresent(retrigger, forKey: AnyKey("retrigger"))
        try c.encodeIfPresent(activation, forKey: AnyKey("activation"))
    }
}

extension HumVoice: Codable {
    static let knownKeys: Set<String> = ["identifier", "rate", "pitch", "volume"]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        identifier = try c.decodeIfPresent(String.self, forKey: AnyKey("identifier"))
        rate = try c.decodeIfPresent(Double.self, forKey: AnyKey("rate"))
        pitch = try c.decodeIfPresent(Double.self, forKey: AnyKey("pitch"))
        volume = try c.decodeIfPresent(Double.self, forKey: AnyKey("volume"))
        extra = try c.unknownFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encodeUnknownFields(extra)
        try c.encodeIfPresent(identifier, forKey: AnyKey("identifier"))
        try c.encodeIfPresent(rate, forKey: AnyKey("rate"))
        try c.encodeIfPresent(pitch, forKey: AnyKey("pitch"))
        try c.encodeIfPresent(volume, forKey: AnyKey("volume"))
    }
}

// MARK: - Encoding helpers

extension HumDocument {
    /// Pretty, key-sorted JSON so diffs stay small when a person or an agent edits the file.
    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
