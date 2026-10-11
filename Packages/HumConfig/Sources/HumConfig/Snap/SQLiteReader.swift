// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A tiny read-only SQLite reader, so HumConfig can open TD Snap page sets (`.sps`) without linking
/// SQLite (which isn't part of Foundation on Linux).
///
/// It only does what the Snap importer needs: list a table's rows, or find one row by its rowid.
/// It follows the file format at https://www.sqlite.org/fileformat2.html and never writes.
struct SQLiteReader {
    enum Value: Equatable {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob([UInt8])

        var int: Int? {
            switch self {
            case .integer(let v): Int(v)
            case .real(let v): Int(v)
            case .text(let s): Int(s)
            default: nil
            }
        }

        var string: String? {
            switch self {
            case .text(let s): s
            case .integer(let v): String(v)
            default: nil
            }
        }

        var bytes: [UInt8]? {
            if case .blob(let b) = self { return b }
            return nil
        }
    }

    /// One table row, read by column name.
    struct Row {
        let rowid: Int64
        let values: [String: Value]

        subscript(_ column: String) -> Value { values[column] ?? .null }
    }

    struct Malformed: Error, CustomStringConvertible {
        let description: String
    }

    private let bytes: [UInt8]
    private let pageSize: Int
    private let usableSize: Int
    private var tables: [String: (rootPage: Int, columns: [String], rowidColumn: String?)] = [:]

    init(_ data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count >= 100, String(decoding: bytes[0..<15], as: UTF8.self) == "SQLite format 3" else {
            throw Malformed(description: "not an SQLite database")
        }
        let size = Int(bytes[16]) << 8 | Int(bytes[17])
        pageSize = size == 1 ? 65536 : size
        usableSize = pageSize - Int(bytes[20])
        guard pageSize >= 512, usableSize >= 480 else { throw Malformed(description: "bad page size") }
        guard Self.uint32(bytes, 56) <= 1 else { throw Malformed(description: "only UTF-8 databases are supported") }

        // sqlite_schema lives in the b-tree rooted at page 1.
        var found: [String: (Int, [String], String?)] = [:]
        try scan(page: 1) { _, values in
            guard values.count >= 5, values[0] == .text("table"),
                  case .text(let name) = values[1], let root = values[3].int, case .text(let sql) = values[4]
            else { return }
            let (columns, rowidColumn) = Self.columns(fromCreateTable: sql)
            found[name] = (root, columns, rowidColumn)
        }
        tables = found.mapValues { (rootPage: $0.0, columns: $0.1, rowidColumn: $0.2) }
    }

    func hasTable(_ name: String) -> Bool { tables[name] != nil }

    /// Every row of `table`, in rowid order. Columns added later with ALTER TABLE read as NULL in
    /// rows written before them.
    func rows(_ table: String) throws -> [Row] {
        guard let t = tables[table] else { throw Malformed(description: "no table \(table)") }
        var out: [Row] = []
        try scan(page: t.rootPage) { rowid, values in
            out.append(Self.row(rowid: rowid, values: values, columns: t.columns, rowidColumn: t.rowidColumn))
        }
        return out
    }

    /// The row whose rowid (INTEGER PRIMARY KEY) is `rowid`, found by walking down the b-tree.
    func row(_ table: String, rowid: Int64) throws -> Row? {
        guard let t = tables[table] else { throw Malformed(description: "no table \(table)") }
        var page = t.rootPage
        for _ in 0..<64 {
            let (base, header) = pageStart(page)
            let type = bytes[header]
            let count = Self.uint16(bytes, header + 3)
            if type == 0x05 {
                var next = Self.uint32(bytes, header + 8)
                for i in 0..<count {
                    let cell = base + Self.uint16(bytes, header + 12 + 2 * i)
                    let (key, _) = Self.varint(bytes, cell + 4)
                    if rowid <= key { next = Self.uint32(bytes, cell); break }
                }
                page = next
            } else if type == 0x0D {
                for i in 0..<count {
                    let cell = base + Self.uint16(bytes, header + 8 + 2 * i)
                    let (key, values) = try leafCell(at: cell)
                    if key == rowid {
                        return Self.row(rowid: key, values: values, columns: t.columns, rowidColumn: t.rowidColumn)
                    }
                }
                return nil
            } else {
                throw Malformed(description: "unexpected page type \(type)")
            }
        }
        throw Malformed(description: "b-tree too deep")
    }

    // MARK: - B-tree pages

    /// Start of a page, and of its b-tree header (page 1 has the 100-byte file header first).
    private func pageStart(_ page: Int) -> (base: Int, header: Int) {
        let base = (page - 1) * pageSize
        return (base, page == 1 ? 100 : base)
    }

    private func scan(page: Int, depth: Int = 0, _ visit: (Int64, [Value]) throws -> Void) throws {
        guard page >= 1, page * pageSize <= bytes.count, depth < 64 else {
            throw Malformed(description: "page \(page) is out of range")
        }
        let (base, header) = pageStart(page)
        let type = bytes[header]
        let count = Self.uint16(bytes, header + 3)
        switch type {
        case 0x05:  // interior table page: child pointers, then the right-most child
            for i in 0..<count {
                let cell = base + Self.uint16(bytes, header + 12 + 2 * i)
                try scan(page: Self.uint32(bytes, cell), depth: depth + 1, visit)
            }
            try scan(page: Self.uint32(bytes, header + 8), depth: depth + 1, visit)
        case 0x0D:  // leaf table page: the rows
            for i in 0..<count {
                let (rowid, values) = try leafCell(at: base + Self.uint16(bytes, header + 8 + 2 * i))
                try visit(rowid, values)
            }
        default:
            throw Malformed(description: "unexpected page type \(type)")
        }
    }

    private func leafCell(at offset: Int) throws -> (Int64, [Value]) {
        let (payloadSize, n1) = Self.varint(bytes, offset)
        let (rowid, n2) = Self.varint(bytes, offset + n1)
        let start = offset + n1 + n2
        let payload = try readPayload(at: start, size: Int(payloadSize))
        return (rowid, try Self.record(payload))
    }

    /// A cell's payload, following overflow pages when it doesn't fit on its page.
    private func readPayload(at start: Int, size: Int) throws -> [UInt8] {
        let maxLocal = usableSize - 35
        if size <= maxLocal { return Array(bytes[start..<start + size]) }
        let minLocal = (usableSize - 12) * 32 / 255 - 23
        let k = minLocal + (size - minLocal) % (usableSize - 4)
        let local = k <= maxLocal ? k : minLocal
        var out = Array(bytes[start..<start + local])
        out.reserveCapacity(size)
        var next = Self.uint32(bytes, start + local)
        var guardCount = 0
        while out.count < size {
            guard next >= 1, next * pageSize <= bytes.count, guardCount < 1_000_000 else {
                throw Malformed(description: "broken overflow chain")
            }
            let base = (next - 1) * pageSize
            let take = min(usableSize - 4, size - out.count)
            out.append(contentsOf: bytes[base + 4..<base + 4 + take])
            next = Self.uint32(bytes, base)
            guardCount += 1
        }
        return out
    }

    // MARK: - Records

    private static func record(_ p: [UInt8]) throws -> [Value] {
        let (headerSize, n) = varint(p, 0)
        var types: [Int64] = []
        var i = n
        while i < Int(headerSize) {
            let (t, len) = varint(p, i)
            types.append(t)
            i += len
        }
        var body = Int(headerSize)
        var values: [Value] = []
        for t in types {
            let len = serialLength(t)
            guard body + len <= p.count else { throw Malformed(description: "record runs past its payload") }
            let field = p[body..<body + len]
            switch t {
            case 0: values.append(.null)
            case 1...6: values.append(.integer(signedInt(field)))
            case 7: values.append(.real(Double(bitPattern: UInt64(bitPattern: signedInt(field)))))
            case 8: values.append(.integer(0))
            case 9: values.append(.integer(1))
            default:
                values.append(t % 2 == 0 ? .blob(Array(field)) : .text(String(decoding: field, as: UTF8.self)))
            }
            body += len
        }
        return values
    }

    private static func serialLength(_ t: Int64) -> Int {
        switch t {
        case 0, 8, 9: 0
        case 1: 1
        case 2: 2
        case 3: 3
        case 4: 4
        case 5: 6
        case 6, 7: 8
        default: t >= 12 ? Int((t - 12) / 2) : 0
        }
    }

    private static func signedInt(_ field: ArraySlice<UInt8>) -> Int64 {
        var v: Int64 = field.first.map { $0 & 0x80 != 0 ? -1 : 0 } ?? 0
        for b in field { v = (v << 8) | Int64(b) }
        return v
    }

    private static func row(rowid: Int64, values: [Value], columns: [String], rowidColumn: String?) -> Row {
        var dict: [String: Value] = [:]
        for (i, name) in columns.enumerated() {
            dict[name] = i < values.count ? values[i] : .null
        }
        // An INTEGER PRIMARY KEY column is stored as NULL; its value is the rowid.
        if let rowidColumn { dict[rowidColumn] = .integer(rowid) }
        return Row(rowid: rowid, values: dict)
    }

    // MARK: - Schema SQL

    /// Column names from a CREATE TABLE statement, and which one (if any) is the rowid alias.
    static func columns(fromCreateTable sql: String) -> ([String], String?) {
        guard let open = sql.firstIndex(of: "("), let close = sql.lastIndex(of: ")"), open < close else { return ([], nil) }
        var parts: [String] = []
        var depth = 0, current = ""
        for ch in sql[sql.index(after: open)..<close] {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth -= 1 }
            if ch == ",", depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current)

        let constraints: Set<String> = ["PRIMARY", "FOREIGN", "UNIQUE", "CHECK", "CONSTRAINT"]
        var names: [String] = []
        var rowidColumn: String?
        for part in parts {
            let def = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = def.split(whereSeparator: \.isWhitespace).first else { continue }
            if constraints.contains(first.uppercased()) { continue }
            let name = first.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`[]"))
            names.append(name)
            let squashed = def.uppercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if squashed.contains("INTEGER PRIMARY KEY") { rowidColumn = name }
        }
        return (names, rowidColumn)
    }

    // MARK: - Integers

    static func varint(_ b: [UInt8], _ offset: Int) -> (Int64, Int) {
        var v: UInt64 = 0
        for i in 0..<8 {
            let byte = b[offset + i]
            v = (v << 7) | UInt64(byte & 0x7F)
            if byte & 0x80 == 0 { return (Int64(bitPattern: v), i + 1) }
        }
        v = (v << 8) | UInt64(b[offset + 8])
        return (Int64(bitPattern: v), 9)
    }

    private static func uint16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) << 8 | Int(b[o + 1]) }

    private static func uint32(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
    }
}
