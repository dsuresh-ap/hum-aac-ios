// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Any JSON value. We use it in two places:
/// 1. To keep unknown fields from config files, so they are never dropped (forward compatibility).
/// 2. As the input to the JSON Schema validator.
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Parses raw JSON bytes. Throws `HumConfigError.notJSON` on malformed input.
    public static func parse(_ data: Data) throws -> JSONValue {
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw HumConfigError.notJSON
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let items) = self, items.indices.contains(index) { return items[index] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        if case .number(let n) = self, n == n.rounded(), abs(n) < 1e15 { return Int(n) }
        return nil
    }

    /// The JSON Schema type name of this value. Integers count as "integer" and "number".
    var schemaTypeNames: Set<String> {
        switch self {
        case .null: return ["null"]
        case .bool: return ["boolean"]
        case .number(let n): return n == n.rounded() && n.isFinite ? ["number", "integer"] : ["number"]
        case .string: return ["string"]
        case .array: return ["array"]
        case .object: return ["object"]
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .number(let n):
            // Write whole numbers without ".0" so files stay tidy for humans.
            if n == n.rounded(), abs(n) < 1e15 { try container.encode(Int(n)) } else { try container.encode(n) }
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

/// A coding key that can hold any string. Used to read and write unknown fields.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer where Key == AnyKey {
    /// Collects every key that is not in `known` into a dictionary of raw JSON values.
    func unknownFields(excluding known: Set<String>) throws -> [String: JSONValue] {
        var extra: [String: JSONValue] = [:]
        for key in allKeys where !known.contains(key.stringValue) {
            extra[key.stringValue] = try decode(JSONValue.self, forKey: key)
        }
        return extra
    }
}

extension KeyedEncodingContainer where Key == AnyKey {
    mutating func encodeUnknownFields(_ extra: [String: JSONValue]) throws {
        for (key, value) in extra { try encode(value, forKey: AnyKey(key)) }
    }
}
