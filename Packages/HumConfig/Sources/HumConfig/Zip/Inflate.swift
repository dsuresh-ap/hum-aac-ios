// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A small, dependency-free DEFLATE decoder (RFC 1951), modeled on zlib's `puff.c`.
///
/// It favors clarity over speed. On Apple platforms `ZipArchive` uses the system Compression
/// framework first and only falls back to this, so this mostly runs on Linux (CI, `hum-config`).
enum Inflate {
    struct Failure: Error {}

    /// With `expectedSize`, output stops there: a stream that unpacks to more is rejected instead of
    /// filling memory.
    static func decompress(_ input: Data, expectedSize: Int? = nil) throws -> Data {
        var state = State(input: [UInt8](input))
        if let expectedSize {
            state.limit = expectedSize
            state.output.reserveCapacity(expectedSize)
        }
        var last = false
        while !last {
            last = try state.bits(1) == 1
            switch try state.bits(2) {
            case 0: try state.stored()
            case 1: try state.codes(lengths: FixedTables.shared.lengths, distances: FixedTables.shared.distances)
            case 2: try state.dynamic()
            default: throw Failure()
            }
        }
        return Data(state.output)
    }

    /// Canonical Huffman table: `counts[len]` codes of each length, `symbols` in code order.
    struct Huffman {
        var counts: [Int]
        var symbols: [Int]

        init(lengths: [Int]) throws {
            counts = Array(repeating: 0, count: 16)
            for len in lengths { counts[len] += 1 }
            if counts[0] == lengths.count {  // no codes: valid but useless
                symbols = []
                return
            }
            var left = 1
            for len in 1...15 {
                left <<= 1
                left -= counts[len]
                if left < 0 { throw Failure() }  // over-subscribed
            }
            var offsets = Array(repeating: 0, count: 16)
            for len in 1..<15 { offsets[len + 1] = offsets[len] + counts[len] }
            symbols = Array(repeating: 0, count: lengths.count)
            for (symbol, len) in lengths.enumerated() where len != 0 {
                symbols[offsets[len]] = symbol
                offsets[len] += 1
            }
        }
    }

    final class FixedTables: @unchecked Sendable {
        static let shared = FixedTables()
        let lengths: Huffman
        let distances: Huffman
        private init() {
            var l = [Int](repeating: 8, count: 288)
            for i in 144..<256 { l[i] = 9 }
            for i in 256..<280 { l[i] = 7 }
            // Force-try is safe: these are the fixed tables from RFC 1951 §3.2.6.
            lengths = try! Huffman(lengths: l)
            distances = try! Huffman(lengths: [Int](repeating: 5, count: 30))
        }
    }

    static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    struct State {
        let input: [UInt8]
        var position = 0
        var bitBuffer = 0
        var bitCount = 0
        var output: [UInt8] = []
        var limit = Int.max

        init(input: [UInt8]) { self.input = input }

        mutating func bits(_ need: Int) throws -> Int {
            var value = bitBuffer
            while bitCount < need {
                guard position < input.count else { throw Failure() }
                value |= Int(input[position]) << bitCount
                position += 1
                bitCount += 8
            }
            bitBuffer = value >> need
            bitCount -= need
            return value & ((1 << need) - 1)
        }

        mutating func stored() throws {
            bitBuffer = 0
            bitCount = 0
            guard position + 4 <= input.count else { throw Failure() }
            let len = Int(input[position]) | Int(input[position + 1]) << 8
            let nlen = Int(input[position + 2]) | Int(input[position + 3]) << 8
            guard len == (~nlen & 0xFFFF) else { throw Failure() }
            position += 4
            guard position + len <= input.count, output.count + len <= limit else { throw Failure() }
            output.append(contentsOf: input[position..<(position + len)])
            position += len
        }

        mutating func decode(_ h: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for len in 1...15 {
                code |= try bits(1)
                let count = h.counts[len]
                if code - count < first { return h.symbols[index + (code - first)] }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw Failure()
        }

        mutating func codes(lengths: Huffman, distances: Huffman) throws {
            while true {
                var symbol = try decode(lengths)
                if symbol < 256 {
                    guard output.count < limit else { throw Failure() }
                    output.append(UInt8(symbol))
                } else if symbol == 256 {
                    return
                } else {
                    symbol -= 257
                    guard symbol < 29 else { throw Failure() }
                    let len = Inflate.lengthBase[symbol] + (try bits(Inflate.lengthExtra[symbol]))
                    let dsym = try decode(distances)
                    guard dsym < 30 else { throw Failure() }
                    let dist = Inflate.distBase[dsym] + (try bits(Inflate.distExtra[dsym]))
                    guard dist <= output.count, output.count + len <= limit else { throw Failure() }
                    let start = output.count - dist
                    for i in 0..<len { output.append(output[start + i]) }
                }
            }
        }

        mutating func dynamic() throws {
            let nlen = try bits(5) + 257
            let ndist = try bits(5) + 1
            let ncode = try bits(4) + 4
            guard nlen <= 286, ndist <= 30 else { throw Failure() }

            let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
            var codeLengths = [Int](repeating: 0, count: 19)
            for i in 0..<ncode { codeLengths[order[i]] = try bits(3) }
            let lencode = try Huffman(lengths: codeLengths)

            var lengths = [Int](repeating: 0, count: nlen + ndist)
            var index = 0
            while index < nlen + ndist {
                var symbol = try decode(lencode)
                if symbol < 16 {
                    lengths[index] = symbol
                    index += 1
                } else {
                    var len = 0
                    if symbol == 16 {
                        guard index > 0 else { throw Failure() }
                        len = lengths[index - 1]
                        symbol = 3 + (try bits(2))
                    } else if symbol == 17 {
                        symbol = 3 + (try bits(3))
                    } else {
                        symbol = 11 + (try bits(7))
                    }
                    guard index + symbol <= nlen + ndist else { throw Failure() }
                    for _ in 0..<symbol {
                        lengths[index] = len
                        index += 1
                    }
                }
            }
            guard lengths[256] != 0 else { throw Failure() }  // must have an end-of-block code
            let lengthTable = try Huffman(lengths: Array(lengths[0..<nlen]))
            let distTable = try Huffman(lengths: Array(lengths[nlen...]))
            try codes(lengths: lengthTable, distances: distTable)
        }
    }
}
