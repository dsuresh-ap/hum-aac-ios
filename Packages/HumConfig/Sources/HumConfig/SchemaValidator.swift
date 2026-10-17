// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A small JSON Schema (draft 2020-12) validator with no dependencies.
///
/// It supports only the keywords that `hum.schema.json` uses:
/// `type, properties, required, additionalProperties, items, minItems, maxItems, enum, const,
/// minLength, maxLength, minimum, maximum, pattern, format ("uuid"), $ref ("#/$defs/…")`.
/// Unknown keywords (like `description` and `examples`) are ignored, as the spec allows.
/// If you add a keyword to the schema, add it here too (a test fails if the schema uses one we skip).
public struct SchemaValidator: Sendable {
    public static let supportedKeywords: Set<String> = [
        "$schema", "$id", "$defs", "$ref", "$comment", "title", "description", "examples", "default",
        "type", "properties", "required", "additionalProperties", "items", "minItems", "maxItems",
        "enum", "const", "minLength", "maxLength", "minimum", "maximum", "pattern", "format",
    ]

    let schema: JSONValue

    public init(schema: JSONValue) {
        self.schema = schema
    }

    /// The schema that ships with HumConfig (a copy of `schema/hum.schema.json`).
    public static let hum: SchemaValidator = {
        guard
            let url = Bundle.module.url(forResource: "hum.schema", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONValue.parse(data)
        else {
            fatalError("hum.schema.json is missing from the HumConfig bundle")
        }
        return SchemaValidator(schema: json)
    }()

    /// Validates `value` and returns friendly issues. An empty array means the value is valid.
    public func validate(_ value: JSONValue) -> [ValidationIssue] {
        var raw: [RawIssue] = []
        check(value, against: schema, pointer: [], into: &raw)
        // Several keywords can produce the same sentence (e.g. minLength and pattern); show it once.
        var seen: Set<String> = []
        return raw.map { $0.friendly(root: value) }.filter { seen.insert($0.message + $0.path).inserted }
    }

    // MARK: - Core

    private func resolve(_ ref: String) -> JSONValue? {
        guard ref.hasPrefix("#/") else { return nil }
        var node: JSONValue? = schema
        for part in ref.dropFirst(2).split(separator: "/") {
            node = node?[String(part)]
        }
        return node
    }

    private func check(_ value: JSONValue, against schema: JSONValue, pointer: [String], into issues: inout [RawIssue]) {
        guard case .object(let s) = schema else { return }  // `true`/`{}` schemas accept anything

        if let ref = s["$ref"]?.stringValue, let target = resolve(ref) {
            check(value, against: target, pointer: pointer, into: &issues)
        }

        if let typeSpec = s["type"] {
            let allowed: [String]
            switch typeSpec {
            case .string(let t): allowed = [t]
            case .array(let ts): allowed = ts.compactMap(\.stringValue)
            default: allowed = []
            }
            if !allowed.isEmpty, value.schemaTypeNames.isDisjoint(with: allowed) {
                issues.append(RawIssue(pointer: pointer, kind: .type(expected: allowed)))
                return  // further checks would only add noise
            }
        }

        if case .array(let options)? = s["enum"], !options.contains(value) {
            issues.append(RawIssue(pointer: pointer, kind: .enumeration(options.compactMap(\.stringValue))))
        }
        if let constant = s["const"], constant != value {
            issues.append(RawIssue(pointer: pointer, kind: .constant(constant)))
        }

        switch value {
        case .string(let str):
            if let min = s["minLength"]?.intValue, str.count < min {
                issues.append(RawIssue(pointer: pointer, kind: .tooShort(min)))
            }
            if let max = s["maxLength"]?.intValue, str.count > max {
                issues.append(RawIssue(pointer: pointer, kind: .tooLong(max)))
            }
            if let pattern = s["pattern"]?.stringValue,
               str.range(of: pattern, options: .regularExpression) == nil {
                issues.append(RawIssue(pointer: pointer, kind: .pattern))
            }
            if s["format"]?.stringValue == "uuid", UUID(uuidString: str) == nil {
                issues.append(RawIssue(pointer: pointer, kind: .uuid))
            }

        case .number(let n):
            if case .number(let min)? = s["minimum"], n < min {
                issues.append(RawIssue(pointer: pointer, kind: .range(min: min, max: s["maximum"].flatMap(Self.number))))
            } else if case .number(let max)? = s["maximum"], n > max {
                issues.append(RawIssue(pointer: pointer, kind: .range(min: s["minimum"].flatMap(Self.number), max: max)))
            }

        case .array(let items):
            if let min = s["minItems"]?.intValue, items.count < min {
                issues.append(RawIssue(pointer: pointer, kind: .tooFewItems(min)))
            }
            if let max = s["maxItems"]?.intValue, items.count > max {
                issues.append(RawIssue(pointer: pointer, kind: .tooManyItems(max)))
            }
            if let itemSchema = s["items"] {
                for (index, item) in items.enumerated() {
                    check(item, against: itemSchema, pointer: pointer + [String(index)], into: &issues)
                }
            }

        case .object(let dict):
            if case .array(let required)? = s["required"] {
                for key in required.compactMap(\.stringValue) where dict[key] == nil {
                    issues.append(RawIssue(pointer: pointer + [key], kind: .missing))
                }
            }
            let properties: [String: JSONValue]
            if case .object(let p)? = s["properties"] { properties = p } else { properties = [:] }
            for (key, child) in dict {
                if let childSchema = properties[key] {
                    check(child, against: childSchema, pointer: pointer + [key], into: &issues)
                } else if let additional = s["additionalProperties"] {
                    if additional == .bool(false) {
                        issues.append(RawIssue(pointer: pointer + [key], kind: .notAllowed))
                    } else {
                        check(child, against: additional, pointer: pointer + [key], into: &issues)
                    }
                }
            }

        case .null, .bool:
            break
        }
    }

    private static func number(_ v: JSONValue) -> Double? {
        if case .number(let n) = v { return n }
        return nil
    }
}

// MARK: - Friendly messages

private struct RawIssue {
    enum Kind {
        case type(expected: [String])
        case enumeration([String])
        case constant(JSONValue)
        case tooShort(Int), tooLong(Int)
        case pattern, uuid
        case range(min: Double?, max: Double?)
        case tooFewItems(Int), tooManyItems(Int)
        case missing, notAllowed
    }

    var pointer: [String]
    var kind: Kind

    func friendly(root: JSONValue) -> ValidationIssue {
        let path = "/" + pointer.joined(separator: "/")
        let field = pointer.last ?? "file"
        let owner = Self.describeOwner(of: pointer, root: root)

        let problem: ConfigProblem
        switch (field, kind) {
        case ("spokenText", .missing), ("spokenText", .tooShort), ("spokenText", .pattern): problem = .noWords(owner)
        case ("label", .tooShort), ("label", .pattern): problem = .emptyLabel(owner)
        case ("name", .missing), ("name", .tooShort), ("name", .pattern): problem = .noName(owner)
        case ("id", .missing): problem = .missingID(owner)
        case (_, .uuid): problem = .invalidID(owner, field: field)
        case ("row", .missing), ("column", .missing): problem = .noPlace(owner)
        case ("formatVersion", .missing): problem = .noFormatVersion
        case (_, .missing): problem = .missingField(owner, field: field)
        case (_, .type(let expected)): problem = .wrongType(owner, field: field, expected: expected)
        case (_, .enumeration(let options)): problem = .notOneOf(owner, field: field, options: options)
        case (_, .constant(let c)): problem = .mustBe(owner, field: field, value: Self.literal(c))
        case (_, .tooShort(let n)): problem = .tooShort(owner, field: field, min: n)
        case (_, .tooLong(let n)): problem = .tooLong(owner, field: field, max: n)
        case ("color", .pattern): problem = .badColor(owner)
        case (_, .pattern): problem = .wrongFormat(owner, field: field)
        case (_, .range(let min, let max)):
            problem = .outOfRange(owner, field: field, min: min.map { Self.literal(.number($0)) } ?? "…",
                                  max: max.map { Self.literal(.number($0)) } ?? "…")
        case (_, .tooFewItems(let n)): problem = .tooFewItems(owner, field: field, min: n)
        case (_, .tooManyItems(let n)): problem = .tooManyItems(owner, field: field, max: n)
        case (_, .notAllowed): problem = .notAllowed(owner, field: field)
        }
        return ValidationIssue(.error, problem, path: path)
    }

    /// Turns a JSON pointer into the board or tile it's about, e.g. ["boards","0","tiles","2","spokenText"] → tile "snack".
    static func describeOwner(of pointer: [String], root: JSONValue) -> ConfigSubject {
        if pointer.count >= 4, pointer[0] == "boards", pointer[2] == "tiles",
           let b = Int(pointer[1]), let t = Int(pointer[3]) {
            let tile = root["boards"]?[b]?["tiles"]?[t]
            let name = tile?["label"]?.stringValue ?? tile?["spokenText"]?.stringValue
            if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return .tile(name) }
            return .tileNumber(t + 1, boardName: root["boards"]?[b]?["name"]?.stringValue, boardNumber: b + 1)
        }
        if pointer.count >= 2, pointer[0] == "boards", let b = Int(pointer[1]) {
            if let name = root["boards"]?[b]?["name"]?.stringValue, !name.isEmpty { return .board(name) }
            return .boardNumber(b + 1)
        }
        if pointer.first == "settings" { return .settings }
        return .file
    }

    static func literal(_ v: JSONValue) -> String {
        switch v {
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .string(let s): return "\"\(s)\""
        case .bool(let b): return String(b)
        default: return "\(v)"
        }
    }
}
