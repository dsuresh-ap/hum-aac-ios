// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import HumConfig

/// `Fixtures/mini.sps` is a made-up TD Snap page set written by `Fixtures/make-mini-sps.py`.
private func miniSPS() throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/mini.sps"))
}

private func uuid(_ s: String) -> UUID { UUID(uuidString: s)! }

private let homeID = uuid("11111111-0000-4000-8000-000000000001")
private let protestsID = uuid("11111111-0000-4000-8000-000000000002")
private let protests2ID = uuid("11111111-0000-4000-8000-000000000003")
private let scaleID = uuid("11111111-0000-4000-8000-000000000005")

@Suite("SQLite reader")
struct SQLiteReaderTests {
    @Test func readsEveryRowAcrossInteriorPages() throws {
        let db = try SQLiteReader(try miniSPS())
        // 300 filler rows don't fit on one 1 KB page, so the table has interior b-tree pages.
        let buttons = try db.rows("Button")
        #expect(buttons.count == 335)
        #expect(buttons.map(\.rowid) == buttons.map(\.rowid).sorted())
        #expect(buttons.last?["Label"] == .text("filler 299"))
    }

    @Test func readsBlobsThatSpillOntoOverflowPages() throws {
        let db = try SQLiteReader(try miniSPS())
        let wmf = try #require(try db.row("PageSetData", rowid: 1)?["Data"].bytes)
        #expect(wmf.count > 1024)
        #expect(wmf.starts(with: [0xD7, 0xCD, 0xC6, 0x9A]))
        #expect(try db.row("PageSetData", rowid: 99) == nil)
    }

    @Test func integerPrimaryKeyReadsAsRowid() throws {
        let db = try SQLiteReader(try miniSPS())
        let page = try #require(try db.rows("Page").first)
        #expect(page["Id"] == .integer(page.rowid))
    }

    @Test func parsesColumnNamesFromCreateTable() {
        let (columns, rowid) = SQLiteReader.columns(fromCreateTable: """
            CREATE TABLE 'ButtonPageLink' ('Id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `ButtonId` INTEGER NOT NULL,
            "PageUniqueId" varchar(36) NOT NULL DEFAULT('x,y'), FOREIGN KEY('ButtonId') REFERENCES 'Button'('Id'))
            """)
        #expect(columns == ["Id", "ButtonId", "PageUniqueId"])
        #expect(rowid == "Id")
    }

    @Test func rejectsFilesThatArentSQLite() {
        #expect(throws: (any Error).self) { try SQLiteReader(Data("hello".utf8)) }
    }
}

@Suite("TD Snap import")
struct SnapImporterTests {
    @Test func keepsSnapIDsAndPositions() throws {
        let result = try SnapImporter.convert(try miniSPS())
        let home = try #require(result.document.homeBoard)
        #expect(home.id == homeID)
        #expect(home.name == "Home page")
        #expect((home.columns, home.rows) == (6, 5))
        let outside = try #require(home.tiles.first { $0.label == "outside" })
        #expect(outside.spokenText == "Let's go outside!")  // Snap's message, not its label
        #expect((outside.row, outside.column) == (0, 1))
        #expect(outside.id == uuid("22222222-0000-4000-8000-000000000003"))
        let folder = try #require(home.tiles.first { $0.label == "Stop/No" })
        #expect(folder.linkedBoardID == protestsID)
        #expect(folder.spokenText.isEmpty)  // a Snap folder that only opens its page stays silent
        #expect(folder.color == "#99D2D8")
        #expect(home.tiles.first { $0.label == "secret" }?.hidden == true)
    }

    @Test func dropsSnapNavigationColumn() throws {
        let result = try SnapImporter.convert(try miniSPS())
        let protests = try #require(result.document.board(withID: protestsID))
        // Back and Home are gone; the column they used is removed.
        #expect(!protests.tiles.contains { ["Back", "Home"].contains($0.label) })
        #expect(protests.columns == 5)
        let stop = try #require(protests.tiles.first { $0.label == "stop it" })
        #expect((stop.row, stop.column) == (0, 0))
        // "Next page" goes to the bottom-right; that spot was taken, so the board grew a row.
        let next = try #require(protests.tiles.first { $0.label == "Next page" })
        #expect(next.linkedBoardID == protests2ID)
        #expect(protests.rows == 6)
        #expect((next.row, next.column) == (5, 4))
        #expect(stop.function == .protest)
        // Home keeps its first column: real tiles live there.
        #expect(result.document.homeBoard?.tiles.contains { $0.column == 0 } == true)
    }

    @Test func convertsPictures() throws {
        let result = try SnapImporter.convert(try miniSPS())
        let tiles = result.document.boards.flatMap(\.tiles)
        let wmf = try #require(tiles.first { $0.label == "Stop/No" }?.image)
        let emf = try #require(tiles.first { $0.label == "stop it" }?.image)
        let png = try #require(tiles.first { $0.label == "outside" }?.image)
        let wmfSVG = String(decoding: try #require(result.media[wmf]), as: UTF8.self)
        #expect(wmfSVG.hasPrefix("<svg") && wmfSVG.contains("fill=\"#d02030\""))
        let emfSVG = String(decoding: try #require(result.media[emf]), as: UTF8.self)
        #expect(emfSVG.contains("fill=\"#2030ff\"") && emfSVG.contains(" C"))
        #expect(emfSVG.contains("viewBox=\"987 887 426 326\""))  // fitted to the drawing, not the frame
        #expect(png.hasSuffix(".png") && result.media[png]?.starts(with: [0x89, 0x50]) == true)
        // A Snap library symbol isn't in the file: emoji placeholder instead.
        #expect(tiles.first { $0.label == "apple" }?.symbol == "🍎")
    }

    @Test func leavesOutWhatHumCantShow() throws {
        let result = try SnapImporter.convert(try miniSPS())
        let names = Set(result.document.boards.map(\.name))
        #expect(!names.contains("Keyboard (ABC)"))
        #expect(!names.contains("Big scale"))  // 13 columns
        let home = try #require(result.document.homeBoard)
        #expect(!home.tiles.contains { ["Keyboard", "Keys", "Dashboard"].contains($0.label) })
        // The folder to the too-big page now just speaks.
        let big = try #require(home.tiles.first { $0.label == "Big" })
        #expect(big.linkedBoardID == nil && big.spokenText == "Big")
        #expect(result.notes.contains { $0.contains("Big scale (13 × 1)") })
        #expect(result.notes.contains { $0.contains("Home page: Dashboard") })
    }

    @Test func compactsScalePages() throws {
        let scale = try #require(try SnapImporter.convert(try miniSPS()).document.board(withID: scaleID))
        #expect((scale.columns, scale.rows) == (3, 1))
        #expect(scale.tiles.map(\.label) == ["1", "2", "3"])
    }

    @Test func resultIsAValidHumPackage() throws {
        let result = try SnapImporter.convert(try miniSPS())
        let package = try HumPackage.write(result.document, media: result.media)
        let issues = HumConfigLoader.validate(package)
        #expect(!issues.contains { $0.severity == .error })
        #expect(!issues.contains { $0.message.contains("isn't in the file") })
    }

    @Test func rejectsOtherFiles() throws {
        #expect(throws: SnapImporter.ImportError.notSnapFile) { try SnapImporter.convert(Data("not a database".utf8)) }
        #expect(throws: SnapImporter.ImportError.notSnapFile) { try SnapImporter.convert(try example("starter.hum.json")) }
    }
}
