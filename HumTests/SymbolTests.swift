// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import Hum

/// Symbol search parsing and turning symbol pictures into tile images (offline: no network in tests).
@Suite("Symbols")
struct SymbolTests {
    @Test func arasaacResultsParseAndSkipViolentOnes() throws {
        let json = """
            [{"_id": 11461, "keywords": [{"keyword": "juice", "type": 2}], "violence": false},
             {"_id": 99, "keywords": [{"keyword": "fight"}], "violence": true},
             {"_id": 7, "keywords": []}]
            """
        let symbols = try SymbolLibrary.parse(Data(json.utf8))
        #expect(symbols.map(\.id) == ["arasaac-11461", "arasaac-7"])
        #expect(symbols.first?.keyword == "juice")
        #expect(symbols.first?.imageURL.absoluteString == "https://static.arasaac.org/pictograms/11461/11461_500.png")
        #expect(throws: SymbolLibrary.SearchError.self) { try SymbolLibrary.parse(Data("not json".utf8)) }
    }

    @Test func mulberryResultsParse() throws {
        let json = """
            [{"id": 44, "text": "Apple", "picto": {"id": 3160, "symbolset_id": 13,
              "image_url": "https://globalsymbols.com/uploads/x/13_3160.svg", "native_format": "svg"}},
             {"id": 45, "text": "Bad", "picto": {"id": 1, "symbolset_id": 13, "image_url": "http://insecure/x.svg"}}]
            """
        let symbols = try SymbolLibrary.parseGlobalSymbols(Data(json.utf8))
        #expect(symbols.map(\.keyword) == ["Apple"])  // only https images
        #expect(symbols.first?.imageURL.pathExtension == "svg")
    }

    /// A symbol PNG with a see-through background must not turn black as a JPEG.
    @Test func transparentPicturesGetAWhiteBackground() throws {
        let png = try #require(Self.transparentPNG())
        let jpeg = try #require(ImageProcessing.tileImageData(from: png))
        #expect(try Self.cornerBrightness(jpeg) > 0.95)
    }

    /// Mulberry symbols are SVG: NSImage draws them on macOS, WebKit on iOS.
    @MainActor
    @Test func svgSymbolsBecomeTileImages() async throws {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="100" height="50" viewBox="0 0 100 50">
            <circle cx="50" cy="25" r="20" fill="red"/></svg>
            """
        let jpeg = try #require(await ImageProcessing.tileImageDataAllowingSVG(from: Data(svg.utf8)), "SVG should render on this platform")
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(max(image.width, image.height) <= ImageProcessing.maxPixelSize)
        #expect(max(image.width, image.height) >= 256)
        #expect(try Self.cornerBrightness(jpeg) > 0.95)
        #expect(try Self.centerIsRed(jpeg))
        #expect(await ImageProcessing.tileImageDataAllowingSVG(from: Data("hello".utf8)) == nil)
    }

    // MARK: Helpers

    static func transparentPNG() -> Data? {
        guard let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 5, y: 5, width: 10, height: 10))  // corners stay transparent
        guard let image = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static func centerIsRed(_ data: Data) throws -> Bool {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let center = try #require(image.cropping(to: CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(center, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel[0] > 200 && pixel[1] < 80 && pixel[2] < 80
    }

    /// Brightness (0...1) of the top-left pixel.
    static func cornerBrightness(_ data: Data) throws -> Double {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        return Double(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / (3 * 255)
    }
}
