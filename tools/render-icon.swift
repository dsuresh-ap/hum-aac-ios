// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0
//
// Renders Hum's app icon with Core Graphics (no design tools needed, so anyone can tweak it).
//   swift tools/render-icon.swift <variant> <out.png> [size] [--mac] [--dark] [--tinted]
// The app icon is "wave": a gentle hum made of five soft keys on Hum's teal.
// Other variants (phrases, grid) are kept for comparison.

import AppKit
import CoreGraphics

let args = CommandLine.arguments
let variant = args[1], out = args[2]
let size = args.count > 3 ? Double(args[3]) ?? 1024 : 1024
let mac = args.contains("--mac"), dark = args.contains("--dark"), tinted = args.contains("--tinted")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Hum palette (see Theme.swift). Background: teal (light), deep slate (dark), black (tinted, iOS tints it).
let mist: UInt32 = tinted ? 0x000000 : dark ? 0x1B2228 : (variant == "wave" ? 0x3A7F83 : 0xE9EDF0)
let mistDeep: UInt32 = tinted ? 0x000000 : dark ? 0x0F1317 : (variant == "wave" ? 0x255A5E : 0xD3DCE2)
let teal: UInt32 = 0x2F6F73
let faces: [(UInt32, UInt32)] = tinted
    ? [(0xD8D8D8, 0x8A8A8A), (0xC8C8C8, 0x7E7E7E), (0xF2F2F2, 0x9A9A9A), (0xB8B8B8, 0x747474)]
    : dark
    ? [(0x3F5A3B, 0x2A3D27), (0x34536A, 0x243A4A), (0x6A403A, 0x4A2B27), (0x5F5133, 0x433922)]
    : [(0xCFE4C6, 0xA9C79C), (0xC5DFEC, 0x99BFD3), (0xF2CBC2, 0xD9A497), (0xF6DCB4, 0xDDB985)] // moss, sky, rosehip, apricot

let S = CGFloat(size)
// iOS icons are opaque (App Store Connect rejects an alpha channel); only the macOS icon needs one, for its shadow.
let alpha: CGImageAlphaInfo = mac ? .premultipliedLast : .noneSkipLast
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue)!
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: S / 1024, y: -S / 1024)  // draw in a 1024 top-left space

func rr(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }

// Canvas: full-bleed on iOS (the system masks it); macOS draws its own rounded square with a shadow.
var canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
if mac {
    canvas = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: rgb(0x000000, 0.28))
    ctx.addPath(rr(canvas, 185)); ctx.setFillColor(rgb(mist)); ctx.fillPath()
    ctx.restoreGState()
}
ctx.saveGState()
ctx.addPath(rr(canvas, mac ? 185 : 0)); ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(mist), rgb(mistDeep)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: canvas.minY), end: CGPoint(x: 0, y: canvas.maxY), options: [])

// Map a 1024 design onto the canvas.
let k = canvas.width / 1024
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: canvas.minX + x * k, y: canvas.minY + y * k, width: w * k, height: h * k)
}

/// A soft key: darker edge under a face. `pressed` sinks the face onto the edge.
func key(_ r: CGRect, radius: CGFloat, face: UInt32, edge: UInt32, depth: CGFloat, pressed: Bool = false) {
    ctx.addPath(rr(CGRect(x: r.minX, y: r.minY + depth, width: r.width, height: r.height), radius))
    ctx.setFillColor(rgb(edge)); ctx.fillPath()
    let sink = pressed ? depth * 0.8 : 0
    ctx.addPath(rr(CGRect(x: r.minX, y: r.minY + sink, width: r.width, height: r.height), radius))
    ctx.setFillColor(rgb(face)); ctx.fillPath()
}

switch variant {
case "phrases":
    // One big apricot key with three whole-phrase "pills": phrases, not words.
    key(R(172, 196, 680, 600), radius: 150 * k, face: faces[3].0, edge: faces[3].1, depth: 34 * k)
    let pills: [(CGFloat, Int)] = [(470, 0), (380, 1), (300, 2)]
    for (i, p) in pills.enumerated() {
        let r = R(262, 300 + CGFloat(i) * 136, p.0, 92)
        ctx.addPath(rr(r, 46 * k)); ctx.setFillColor(rgb(faces[p.1].1)); ctx.fillPath()
        ctx.addPath(rr(r.insetBy(dx: 0, dy: 0).offsetBy(dx: 0, dy: -8 * k), 46 * k)); ctx.setFillColor(rgb(faces[p.1].0)); ctx.fillPath()
    }
case "wave":
    // A hum: five soft keys rising and falling like a gentle sound wave.
    let heights: [CGFloat] = [260, 430, 560, 430, 260]
    let colors = [0, 1, 3, 2, 0]
    for i in 0..<5 {
        let h = heights[i], w: CGFloat = 128
        let x = 132 + CGFloat(i) * 158
        key(R(x, 512 - h / 2 - 18, w, h), radius: 64 * k, face: faces[colors[i]].0, edge: faces[colors[i]].1, depth: 26 * k)
    }
case "grid":
    // Four soft keys; the "no thank you" (rosehip) key is pressed, as big as the rest.
    let cells = [(0, 0, 3), (1, 0, 0), (0, 1, 2), (1, 1, 1)]
    for (cx, cy, c) in cells {
        key(R(176 + CGFloat(cx) * 352, 166 + CGFloat(cy) * 352, 320, 320), radius: 84 * k,
            face: faces[c].0, edge: faces[c].1, depth: 30 * k, pressed: c == 2)
    }
default: fatalError("unknown variant")
}
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print(out)
