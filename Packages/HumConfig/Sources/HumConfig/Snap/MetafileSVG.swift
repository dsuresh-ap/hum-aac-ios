// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Turns Windows metafiles (WMF and EMF), the vector format TD Snap uses for its symbols, into SVG,
/// which Hum can draw. Only the records Snap's symbols use are supported: filled and outlined
/// polygons, polylines, Bézier paths and plain text. Anything else is skipped.
enum MetafileSVG {
    /// SVG text for WMF or EMF bytes, or nil if the bytes are neither.
    static func svg(from bytes: [UInt8]) -> String? {
        if bytes.starts(with: [0xD7, 0xCD, 0xC6, 0x9A]) { return wmf(bytes) }
        if bytes.count > 44, bytes.starts(with: [1, 0, 0, 0]), Array(bytes[40..<44]) == Array(" EMF".utf8) { return emf(bytes) }
        return nil
    }

    // MARK: - Shared drawing state

    private struct Brush { var hollow = false; var color = "#ffffff" }
    private struct Pen { var none = false; var color = "#000000"; var width = 1 }
    private enum Object { case brush(Brush), pen(Pen), font(height: Int) }

    private struct Canvas {
        var brush = Brush()
        var pen = Pen()
        var evenOdd = true
        var body = ""

        func attributes(fill: Bool, stroke: Bool) -> String {
            let fillValue = fill && !brush.hollow ? brush.color : "none"
            let strokeValue = stroke && !pen.none
                ? "stroke=\"\(pen.color)\" stroke-width=\"\(max(pen.width, 1))\" stroke-linejoin=\"round\" stroke-linecap=\"round\""
                : "stroke=\"none\""
            return "fill=\"\(fillValue)\" fill-rule=\"\(evenOdd ? "evenodd" : "nonzero")\" \(strokeValue)"
        }

        mutating func path(_ d: String, fill: Bool, stroke: Bool) {
            body += "<path d=\"\(d)\" \(attributes(fill: fill, stroke: stroke))/>"
        }
    }

    private static func document(x: Double, y: Double, width: Double, height: Double, body: String) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(n(x)) \(n(y)) \(n(width)) \(n(height))\" "
            + "width=\"\(n(abs(width)))\" height=\"\(n(abs(height)))\">\(body)</svg>"
    }

    /// A short number: whole numbers without a decimal point.
    private static func n(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }

    private static func points(_ p: [(Int, Int)]) -> String { p.map { "\($0.0),\($0.1)" }.joined(separator: " ") }

    // MARK: - WMF (16-bit Windows metafile with a "placeable" header)

    private static func wmf(_ b: [UInt8]) -> String? {
        let r = Bytes(b)
        guard b.count >= 40 else { return nil }
        let left = r.i16(6), top = r.i16(8), right = r.i16(10), bottom = r.i16(12)
        var origin = (0, 0), extent = (right - left, bottom - top)
        var objects: [Int: Object] = [:]
        var canvas = Canvas()

        func add(_ object: Object) {
            var i = 0
            while objects[i] != nil { i += 1 }
            objects[i] = object
        }
        func colorref(_ o: Int) -> String { String(format: "#%02x%02x%02x", b[o], b[o + 1], b[o + 2]) }
        func pts(_ o: Int, _ count: Int) -> [(Int, Int)] { (0..<count).map { (r.i16(o + 4 * $0), r.i16(o + 4 * $0 + 2)) } }

        var pos = 22 + r.u16(22 + 2) * 2  // placeable header, then the WMF header (its size is in words)
        while pos + 6 <= b.count {
            let size = r.u32(pos), function = r.u16(pos + 4), p = pos + 6
            if function == 0 || size < 3 || pos + size * 2 > b.count { break }
            switch function {
            case 0x020B: origin = (r.i16(p + 2), r.i16(p))  // SETWINDOWORG (y, x)
            case 0x020C: extent = (r.i16(p + 2), r.i16(p))  // SETWINDOWEXT (y, x)
            case 0x0106: canvas.evenOdd = r.u16(p) == 1  // SETPOLYFILLMODE
            case 0x02FC: add(.brush(Brush(hollow: r.u16(p) == 1, color: colorref(p + 2))))  // CREATEBRUSHINDIRECT
            case 0x02FA: add(.pen(Pen(none: r.u16(p) & 0xF == 5, color: colorref(p + 6), width: r.i16(p + 2))))  // CREATEPENINDIRECT
            case 0x012D:  // SELECTOBJECT
                switch objects[r.u16(p)] {
                case .brush(let brush): canvas.brush = brush
                case .pen(let pen): canvas.pen = pen
                default: break
                }
            case 0x01F0: objects[r.u16(p)] = nil  // DELETEOBJECT
            case 0x0538:  // POLYPOLYGON
                let count = r.u16(p)
                var o = p + 2 + 2 * count
                var d: [String] = []
                for i in 0..<count {
                    let c = r.u16(p + 2 + 2 * i)
                    d.append("M" + points(pts(o, c)) + "Z")
                    o += 4 * c
                }
                canvas.path(d.joined(separator: " "), fill: true, stroke: true)
            case 0x0324: canvas.path("M" + points(pts(p + 2, r.u16(p))) + "Z", fill: true, stroke: true)  // POLYGON
            case 0x0325: canvas.path("M" + points(pts(p + 2, r.u16(p))), fill: false, stroke: true)  // POLYLINE
            default: break
            }
            pos += size * 2
        }
        return document(x: Double(origin.0), y: Double(origin.1), width: Double(extent.0), height: Double(extent.1), body: canvas.body)
    }

    // MARK: - EMF (32-bit enhanced metafile)

    private static func emf(_ b: [UInt8]) -> String? {
        let r = Bytes(b)
        let bounds = (r.i32(8), r.i32(12), r.i32(16), r.i32(20))
        var objects: [Int: Object] = [:]
        var canvas = Canvas()
        var fontHeight = 12, textColor = "#000000"
        var inPath = false, path: [String] = [], current = (0, 0)
        var xs: [Int] = [], ys: [Int] = []

        func rgb(_ v: Int) -> String { String(format: "#%02x%02x%02x", v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF) }
        func pts16(_ o: Int, _ count: Int) -> [(Int, Int)] {
            let p = (0..<count).map { (r.i16(o + 4 * $0), r.i16(o + 4 * $0 + 2)) }
            xs += p.map(\.0)
            ys += p.map(\.1)
            return p
        }
        func emit(_ d: String, fill: Bool, stroke: Bool) {
            if inPath { path.append(d) } else { canvas.path(d, fill: fill, stroke: stroke) }
        }
        let stock: [Int: Object] = [
            0: .brush(Brush(color: "#ffffff")), 1: .brush(Brush(color: "#c0c0c0")), 2: .brush(Brush(color: "#808080")),
            3: .brush(Brush(color: "#404040")), 4: .brush(Brush(color: "#000000")), 5: .brush(Brush(hollow: true)),
            6: .pen(Pen(color: "#ffffff")), 7: .pen(Pen(color: "#000000")), 8: .pen(Pen(none: true)),
        ]

        var pos = 0
        while pos + 8 <= b.count {
            let type = r.u32(pos), size = r.u32(pos + 4), p = pos + 8
            if type == 14 || size < 8 || pos + size > b.count { break }  // EOF
            switch type {
            case 19: canvas.evenOdd = r.u32(p) == 1  // SETPOLYFILLMODE
            case 24: textColor = rgb(r.u32(p))  // SETTEXTCOLOR
            case 39: objects[r.u32(p)] = .brush(Brush(hollow: r.u32(p + 4) == 1, color: rgb(r.u32(p + 8))))  // CREATEBRUSHINDIRECT
            case 38: objects[r.u32(p)] = .pen(Pen(none: r.u32(p + 4) & 0xF == 5, color: rgb(r.u32(p + 16)), width: r.i32(p + 8)))  // CREATEPEN
            case 95: objects[r.u32(p)] = .pen(Pen(none: r.u32(p + 20) & 0xF == 5, color: rgb(r.u32(p + 32)), width: r.u32(p + 24)))  // EXTCREATEPEN
            case 82: objects[r.u32(p)] = .font(height: max(abs(r.i32(p + 4)), 1))  // EXTCREATEFONTINDIRECTW
            case 37:  // SELECTOBJECT (high bit = stock object)
                let index = r.u32(p)
                switch index & 0x8000_0000 != 0 ? stock[index & 0x7FFF_FFFF] : objects[index] {
                case .brush(let brush): canvas.brush = brush
                case .pen(let pen): canvas.pen = pen
                case .font(let height): fontHeight = height
                case nil: break
                }
            case 40: objects[r.u32(p)] = nil  // DELETEOBJECT
            case 59: inPath = true; path = []  // BEGINPATH
            case 60: inPath = false  // ENDPATH
            case 61: if inPath { path.append("Z") }  // CLOSEFIGURE
            case 62, 63, 64:  // FILLPATH, STROKEPATH, STROKEANDFILLPATH
                if !path.isEmpty { canvas.path(path.joined(separator: " "), fill: type != 63, stroke: type != 62) }
                path = []
            case 27:  // MOVETOEX
                current = (r.i32(p), r.i32(p + 4))
                xs.append(current.0)
                ys.append(current.1)
                if inPath { path.append("M\(current.0),\(current.1)") }
            case 54:  // LINETO
                let previous = current
                current = (r.i32(p), r.i32(p + 4))
                xs.append(current.0)
                ys.append(current.1)
                emit(inPath ? "L\(current.0),\(current.1)" : "M\(previous.0),\(previous.1) L\(current.0),\(current.1)", fill: false, stroke: true)
            case 85, 86, 87, 88, 89:  // POLYBEZIER16, POLYGON16, POLYLINE16, POLYBEZIERTO16, POLYLINETO16
                let count = r.u32(p + 16)
                let ps = pts16(p + 20, count)
                let start = "M\(current.0),\(current.1) "
                switch type {
                case 88:
                    let curves = stride(from: 0, to: count - count % 3, by: 3).map { "C" + points(Array(ps[$0..<$0 + 3])) }
                    emit((inPath ? "" : start) + curves.joined(separator: " "), fill: false, stroke: true)
                case 89: emit((inPath ? "" : start) + "L" + points(ps), fill: false, stroke: true)
                case 85:
                    guard count >= 4 else { break }
                    let curves = stride(from: 1, to: count - (count - 1) % 3, by: 3).map { "C" + points(Array(ps[$0..<$0 + 3])) }
                    emit("M" + points([ps[0]]) + " " + curves.joined(separator: " "), fill: false, stroke: true)
                case 86: if count > 0 { emit("M" + points([ps[0]]) + " L" + points(Array(ps.dropFirst())) + " Z", fill: true, stroke: true) }
                default: if count > 0 { emit("M" + points([ps[0]]) + " L" + points(Array(ps.dropFirst())), fill: false, stroke: true) }
                }
                if let last = ps.last { current = last }
            case 90, 91:  // POLYPOLYLINE16, POLYPOLYGON16
                let polygons = r.u32(p + 16), total = r.u32(p + 20)
                let ps = pts16(p + 24 + 4 * polygons, total)
                var i = 0, d: [String] = []
                for k in 0..<polygons {
                    let c = r.u32(p + 24 + 4 * k)
                    guard c > 0, i + c <= ps.count else { break }
                    let part = Array(ps[i..<i + c])
                    i += c
                    d.append("M" + points([part[0]]) + " L" + points(Array(part.dropFirst())) + (type == 91 ? " Z" : ""))
                }
                emit(d.joined(separator: " "), fill: type == 91, stroke: true)
            case 84:  // EXTTEXTOUTW
                let x = r.i32(p + 28), y = r.i32(p + 32), chars = r.u32(p + 36), offset = r.u32(p + 40)
                guard pos + offset + 2 * chars <= b.count else { break }
                let units = (0..<chars).map { UInt16(r.u16(pos + offset + 2 * $0)) }
                let text = String(decoding: units, as: UTF16.self)
                    .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                canvas.body += "<text x=\"\(x)\" y=\"\(y + fontHeight)\" font-size=\"\(fontHeight)\" font-family=\"Helvetica\" fill=\"\(textColor)\">\(text)</text>"
            default: break
            }
            pos += size
        }

        // Fit the picture to what was drawn (Snap's EMF frames are often much bigger than the symbol).
        if let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
            let pad = Double(max(maxX - minX, maxY - minY)) * 0.03 + 1
            return document(x: Double(minX) - pad, y: Double(minY) - pad,
                            width: Double(maxX - minX) + 2 * pad, height: Double(maxY - minY) + 2 * pad, body: canvas.body)
        }
        return document(x: Double(bounds.0), y: Double(bounds.1), width: Double(bounds.2 - bounds.0 + 1),
                        height: Double(bounds.3 - bounds.1 + 1), body: canvas.body)
    }
}

/// Little-endian reads that return 0 past the end instead of crashing on a damaged file.
private struct Bytes {
    let b: [UInt8]
    init(_ b: [UInt8]) { self.b = b }

    func u16(_ o: Int) -> Int { o >= 0 && o + 2 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
    func i16(_ o: Int) -> Int { Int(Int16(truncatingIfNeeded: u16(o))) }
    func u32(_ o: Int) -> Int { o >= 0 && o + 4 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 : 0 }
    func i32(_ o: Int) -> Int { Int(Int32(truncatingIfNeeded: u32(o))) }
}
