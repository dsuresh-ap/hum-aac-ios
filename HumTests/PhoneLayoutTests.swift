// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import SwiftData
@testable import Hum

/// Boards too big for a phone get a phone layout of their own, so iPad/Mac and iPhone never fight over
/// one grid size (shrinking for the phone used to send tiles to the tray everywhere).
@MainActor
@Suite("Phone layout")
struct PhoneLayoutTests {
    /// A board filled row by row with `count` tiles named t0, t1, …
    func board(_ model: AppModel, rows: Int, columns: Int, count: Int) throws -> Board {
        let board = model.store.createBoard(name: "Big", rows: rows, columns: columns)
        for i in 0..<count {
            try model.store.addTile(to: board, row: i / columns, column: i % columns, label: "t\(i)", spokenText: "Tile \(i)")
        }
        return board
    }

    func phoneModel() -> AppModel {
        let model = makeModel()
        model.usesPhoneLayout = true
        return model
    }

    @Test func fillsPagesInReadingOrderAndKeepsTheMoreSpotFree() throws {
        let model = phoneModel()
        let big = try board(model, rows: 6, columns: 6, count: 36)
        #expect(model.showsPhoneLayout(big))
        #expect(PhoneLayout.arrange(big))
        let byLabel = Dictionary(uniqueKeysWithValues: (big.tiles ?? []).map { ($0.label, PhoneLayout.spot(of: $0)!) })
        #expect(byLabel["t0"] == .init(page: 0, row: 0, column: 0))
        #expect(byLabel["t4"] == .init(page: 0, row: 1, column: 0))
        // 31 tiles fit on a page; the 32nd spot is "More".
        #expect(byLabel["t30"] == .init(page: 0, row: 7, column: 2))
        #expect(byLabel["t31"] == .init(page: 1, row: 0, column: 0))
        #expect(PhoneLayout.pageCount(big) == 2)
        #expect(!byLabel.values.contains { PhoneLayout.isMoreSpot(row: $0.row, column: $0.column) })
        // Every tile kept its spot on the board's own grid.
        #expect((big.tiles ?? []).allSatisfy { $0.row == Int($0.label.dropFirst())! / 6 })
    }

    @Test func phoneSpotsStayWhenTilesAreAddedLater() throws {
        let model = phoneModel()
        let big = try board(model, rows: 5, columns: 6, count: 10)
        PhoneLayout.arrange(big)
        let before = Dictionary(uniqueKeysWithValues: (big.tiles ?? []).map { ($0.id, PhoneLayout.spot(of: $0)) })
        // Added on a Mac in an empty spot of row 0: on the phone it takes the first free spot instead of
        // pushing anything along.
        let late = try model.store.addTile(to: big, row: 4, column: 5, label: "late", spokenText: "Late!")
        PhoneLayout.arrange(big)
        for tile in big.tiles ?? [] where tile.id != late.id {
            #expect(PhoneLayout.spot(of: tile) == before[tile.id] ?? nil)
        }
        #expect(PhoneLayout.spot(of: late) == .init(page: 0, row: 2, column: 2))
    }

    @Test func childSeesPagesWithMoreAndBackReturns() throws {
        let model = phoneModel()
        let big = try board(model, rows: 6, columns: 6, count: 36)
        model.show(boardID: big.id)
        let first = try #require(model.snapshot)
        #expect((first.rows, first.columns) == (PhoneLayout.rows, PhoneLayout.columns))
        let more = try #require(first.cells[7][3])
        #expect(more.nextPage == 1 && more.label == "More")
        model.tap(more, tapTime: 0)
        #expect(model.snapshot?.page == 1)
        #expect(model.snapshot?.cells[0][0]?.label == "t31")
        #expect(model.snapshot?.cells[7][3] == nil)  // last page: no "More"
        model.goBack()
        #expect(model.snapshot?.page == 0)
        #expect(model.currentBoardID == big.id)
    }

    @Test func smallBoardsUseTheirOwnGridOnAPhone() throws {
        let model = phoneModel()
        let small = try board(model, rows: 3, columns: 4, count: 5)
        #expect(!model.showsPhoneLayout(small))
        model.show(boardID: small.id)
        #expect((model.snapshot?.rows, model.snapshot?.columns) == (3, 4))
    }

    @Test func movingOnThePhoneNeverMovesTheBigLayout() throws {
        let model = phoneModel()
        let big = try board(model, rows: 5, columns: 6, count: 12)
        PhoneLayout.arrange(big)
        let a = try #require((big.tiles ?? []).first { $0.label == "t0" })
        let b = try #require((big.tiles ?? []).first { $0.label == "t5" })
        let (aSpot, bSpot) = (PhoneLayout.spot(of: a), PhoneLayout.spot(of: b))
        #expect(model.store.movePhone(a, to: bSpot!, on: big))
        #expect(PhoneLayout.spot(of: a) == bSpot && PhoneLayout.spot(of: b) == aSpot)  // swapped on the phone
        #expect((a.row, a.column, b.row, b.column) == (0, 0, 0, 5))  // untouched on iPad and Mac
        #expect(!model.store.movePhone(a, to: .init(page: 0, row: 7, column: 3), on: big))  // "More" is kept free
    }

    @Test func movingToAnotherBoardForgetsTheOldPhoneSpot() throws {
        let model = phoneModel()
        let big = try board(model, rows: 5, columns: 6, count: 3)
        let other = try board(model, rows: 5, columns: 6, count: 0)
        PhoneLayout.arrange(big)
        let tile = try #require(big.tiles?.first)
        model.store.moveToBoard(tile, other)
        #expect(tile.phonePage == nil)
        PhoneLayout.arrange(other)
        #expect(PhoneLayout.spot(of: tile) == .init(page: 0, row: 0, column: 0))
    }

    @Test func aTileAddedOnThePhoneGoesWhereTheParentTapped() throws {
        let model = phoneModel()
        let big = try board(model, rows: 5, columns: 6, count: 3)
        PhoneLayout.arrange(big)
        let spot = PhoneLayout.Spot(page: 0, row: 5, column: 1)
        let tile = model.store.addTile(to: big, row: 0, column: 3, phoneSpot: spot) { $0.spokenText = "Hi!" }
        #expect(PhoneLayout.spot(of: tile) == spot)
        #expect((tile.row, tile.column) == (0, 3))
    }
}
