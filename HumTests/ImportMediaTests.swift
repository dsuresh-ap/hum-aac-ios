// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import ImageIO
import CoreGraphics
import SwiftData
import UniformTypeIdentifiers
import HumConfig
@testable import Hum

/// Pictures inside imported `.hum` files are processed like photos added in the app.
@MainActor
@Suite("Imported pictures")
struct ImportMediaTests {
    /// Imports a `.hum` with one new tile in Home's free spot that uses `picture`.
    func importTile(_ model: AppModel, picture: Data, name: String) throws -> Tile {
        var doc = ConfigBridge.export(boards: model.store.boards()).document
        let home = try #require(doc.boards.firstIndex { $0.isHome })
        let spot = try #require(model.store.firstEmptySpot(on: model.home))
        let id = UUID()
        doc.boards[home].tiles = [HumTile(id: id, label: "pic", spokenText: "Look!", row: spot.row, column: spot.column,
                                          image: "media/\(name)")]
        let package = try HumPackage.write(doc, media: ["media/\(name)": picture])
        let service = ImportService(model: model)
        try service.apply(try service.prepare(data: package, fileName: "test.hum"), mode: .merge)
        return try #require(model.home.tiles?.first { $0.id == id })
    }

    static func pixelSize(_ data: Data) throws -> (Int, Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// A big picture with a transparent background, like a symbol PNG made by hand.
    static func bigTransparentPNG() -> Data? {
        guard let context = CGContext(data: nil, width: 2400, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 800, y: 300, width: 800, height: 600))
        return context.makeImage().flatMap { encode($0, as: .png) }
    }

    @Test func bigTransparentPicturesAreResizedOntoWhite() throws {
        let model = makeModel()
        let png = try #require(Self.bigTransparentPNG())
        let tile = try importTile(model, picture: png, name: "big.png")
        let stored = try #require(tile.imageData)
        let (width, height) = try Self.pixelSize(stored)
        #expect(width == 1024 && height == 512)
        #expect(try SymbolTests.cornerBrightness(stored) > 0.95)
    }

    @Test func humsOwnJPEGsAreKeptByteForByte() throws {
        let model = makeModel()
        let png = try #require(Self.bigTransparentPNG())
        let jpeg = try #require(ImageProcessing.tileImageData(from: png))
        let tile = try importTile(model, picture: jpeg, name: "ready.jpg")
        #expect(tile.imageData == jpeg)
    }

    @Test func aFileThatIsNotAPictureIsIgnored() throws {
        let model = makeModel()
        let tile = try importTile(model, picture: Data("not a picture".utf8), name: "broken.jpg")
        #expect(tile.imageData == nil)
    }

    @Test func svgPicturesBecomeJPEGs() async throws {
        SVGRenderer.loadTimeout = .seconds(120)  // a CI simulator can take ~40 s to start WebKit
        let model = makeModel()
        let svg = Data("""
            <svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><circle cx="20" cy="20" r="15" fill="red"/></svg>
            """.utf8)
        let tile = try importTile(model, picture: svg, name: "symbol.svg")
        // macOS draws SVG during the import; iOS right after it, with WebKit.
        await ImportService.renderImportedSVGs(model)
        let stored = try #require(tile.imageData)
        #expect(!ImageProcessing.isSVG(stored))
        #expect(try SymbolTests.centerIsRed(stored))
    }

    /// An import or a synced change can delete tiles while their SVG pictures are being drawn.
    @Test func deletingTilesWhilePicturesAreDrawnDoesNotCrash() async throws {
        let model = makeModel()
        let svg = Data("""
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><circle cx="20" cy="20" r="15" fill="red"/></svg>
            """.utf8)
        for tile in model.home.placedTiles { tile.imageData = svg }
        try model.context.save()
        let drawing = Task { await ImportService.renderImportedSVGs(model) }
        await Task.yield()
        for tile in model.home.tiles ?? [] { model.context.delete(tile) }
        try model.context.save()
        await drawing.value
        #expect(try model.context.fetch(FetchDescriptor<Tile>()).isEmpty)
    }

    /// Big setups prepare their pictures in the background and report each one for the progress bar.
    @Test func importReportsProgressForEveryPicture() async throws {
        let model = makeModel()
        var doc = ConfigBridge.export(boards: model.store.boards()).document
        let home = try #require(doc.boards.firstIndex { $0.isHome })
        let pictures = (0..<3).map { "media/p\($0).png" }
        let png = try #require(Self.bigTransparentPNG())
        doc.boards[home].tiles = doc.boards[home].tiles.enumerated().map { index, tile in
            var tile = tile
            if index < pictures.count { tile.image = pictures[index] }
            return tile
        }
        let package = try HumPackage.write(doc, media: Dictionary(uniqueKeysWithValues: pictures.map { ($0, png) }))
        let service = ImportService(model: model)
        var steps: [ImportService.Progress] = []
        try await service.apply(try service.prepare(data: package, fileName: "big.hum"), mode: .replace) { steps.append($0) }
        #expect(steps.first == .backingUp)
        #expect(steps.contains(.pictures(done: 3, total: 3)))
        #expect(steps.last == .saving)
        let stored = model.home.placedTiles.compactMap(\.imageData)
        #expect(stored.count == 3)
        #expect(try stored.allSatisfy { try Self.pixelSize($0).0 <= 1024 })
    }

    /// Older builds kept imported SVGs as they were, and the Mac showed blank tiles. Launch converts them.
    @Test func svgPicturesSavedByOlderBuildsAreRepaired() async throws {
        SVGRenderer.loadTimeout = .seconds(120)  // a CI simulator can take ~40 s to start WebKit
        let model = makeModel()
        let tile = try #require(model.home.placedTiles.first)
        tile.imageData = Data("""
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><circle cx="20" cy="20" r="15" fill="red"/></svg>
            """.utf8)
        try model.context.save()
        await ImportService.renderImportedSVGs(model)
        let stored = try #require(tile.imageData)
        #expect(!ImageProcessing.isSVG(stored))
        #expect(try SymbolTests.centerIsRed(stored))
    }
}
