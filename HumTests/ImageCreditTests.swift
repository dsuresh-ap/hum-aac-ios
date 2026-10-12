// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import HumConfig
@testable import Hum

/// A symbol's credit and licence travel with its picture: in the store, in exported files and back.
@MainActor
@Suite("Picture credits")
struct ImageCreditTests {
    static let credit = SymbolLibrary.Source.mulberry.credit

    /// A tile-ready JPEG, like a picked symbol.
    func picture() throws -> Data {
        let png = try #require(ImportMediaTests.bigTransparentPNG())
        return try #require(ImageProcessing.tileImageData(from: png))
    }

    /// A tile in Home's first free spot whose picture is a symbol with a credit.
    func symbolTile(_ model: AppModel) throws -> Tile {
        let spot = try #require(model.store.firstEmptySpot(on: model.home))
        let jpeg = try picture()
        return model.store.addTile(to: model.home, row: spot.row, column: spot.column) {
            $0.label = "swing"
            $0.spokenText = "Let's go on the swing!"
            $0.imageData = jpeg
            $0.imageCredit = Self.credit
        }
    }

    @Test func exportThenImportKeepsTheCredit() throws {
        let model = makeModel()
        let tile = try symbolTile(model)
        let (document, media) = ConfigBridge.export(boards: model.store.boards())
        let exported = try #require(document.boards.flatMap(\.tiles).first { $0.id == tile.id })
        #expect(exported.imageCredit == Self.credit)
        let package = try HumPackage.write(document, media: media)
        #expect(try HumPackage.read(package).credits != nil, "The .hum lists the credit in CREDITS.txt")

        let other = makeModel(starter: false)
        let service = ImportService(model: other)
        try service.apply(try service.prepare(data: package, fileName: "shared.hum"), mode: .merge)
        let imported = try #require(other.store.liveTile(tile.id))
        #expect(imported.imageData != nil)
        #expect(imported.imageCredit == Self.credit)
    }

    @Test func aCreditWithoutAPictureIsNotExported() throws {
        let model = makeModel()
        let tile = try symbolTile(model)
        tile.imageData = nil
        let document = ConfigBridge.export(boards: model.store.boards()).document
        #expect(document.boards.flatMap(\.tiles).first { $0.id == tile.id }?.imageCredit == nil)
    }

    @Test func aNewPhotoFromAFileReplacesTheCredit() throws {
        let model = makeModel()
        let tile = try symbolTile(model)
        var (document, _) = ConfigBridge.export(boards: model.store.boards())
        for b in document.boards.indices {
            for t in document.boards[b].tiles.indices where document.boards[b].tiles[t].id == tile.id {
                document.boards[b].tiles[t].image = "media/photo.jpg"
                document.boards[b].tiles[t].imageCredit = nil  // a parent's own photo
            }
        }
        let package = try HumPackage.write(document, media: ["media/photo.jpg": try picture()])
        let service = ImportService(model: model)
        try service.apply(try service.prepare(data: package, fileName: "photo.hum"), mode: .merge)
        #expect(model.store.liveTile(tile.id)?.imageCredit == nil)
    }

    @Test func duplicateAndUndoKeepTheCredit() throws {
        let model = makeModel()
        let tile = try symbolTile(model)
        let copy = try #require(model.store.duplicate(tile))
        #expect(copy.imageCredit == Self.credit)

        let id = tile.id
        model.store.delete(tile)
        model.store.undo()
        #expect(model.store.liveTile(id)?.imageCredit == Self.credit, "Undo brings back the credit with the picture")
    }
}
