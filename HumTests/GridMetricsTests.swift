// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import Testing
@testable import Hum

/// Boards fill the window when they fit and scroll down when they don't. Columns never change.
@Suite("Grid metrics")
struct GridMetricsTests {
    let iPadLandscape = CGSize(width: 1300, height: 640)

    /// The starter (5 columns × 4 rows) still fits an iPad in landscape: no scrolling.
    @Test func starterFitsIPadLandscape() {
        let layout = GridMetrics.layout(in: iPadLandscape, rows: 4, columns: 5, spacing: 12)
        #expect(!layout.scrolls)
        #expect(layout.tileHeight * 4 + 36 <= iPadLandscape.height + 0.5)
    }

    /// A tall board scrolls, with whole rows plus a peek of the next one, and tiles never below 88 pt.
    @Test func tallBoardScrollsWithAPeek() {
        let size = CGSize(width: 800, height: 900)
        let layout = GridMetrics.layout(in: size, rows: 12, columns: 4, spacing: 12)
        #expect(layout.scrolls)
        #expect(layout.tileHeight >= GridMetrics.minimumTile)
        let visible = GridMetrics.visibleRows(in: size, rows: 12, columns: 4, spacing: 12)
        #expect(visible >= 1 && visible < 12)
        let shown = (size.height + 12) / (layout.tileHeight + 12)
        #expect(shown - Double(visible) > 0.2, "Part of the next row shows")
    }

    /// Phone pages are sized to fit, so they never scroll.
    @Test func pagesNeverScroll() {
        let layout = GridMetrics.layout(in: CGSize(width: 800, height: 300), rows: 8, columns: 4, spacing: 8, canScroll: false)
        #expect(!layout.scrolls)
    }

    /// Columns always fill the width, whatever the height.
    @Test func columnsFillTheWidth() {
        for height in [300.0, 900.0, 3000.0] {
            let layout = GridMetrics.layout(in: CGSize(width: 1000, height: height), rows: 10, columns: 6, spacing: 12)
            #expect(abs(layout.tileWidth * 6 + 60 - 1000) < 0.5)
        }
    }

    @Test func maxColumnsKeepsTilesUsable() {
        #expect(GridMetrics.maxColumns(across: 1000, spacing: 12) == 8)
        #expect(GridMetrics.maxColumns(across: 400, spacing: 12) == 4)
        #expect(GridMetrics.maxColumns(across: 50, spacing: 12) == 1)
    }

    // MARK: Folding iPhone, partly folded

    /// No tile touches the fold. The first and last tiles stay at the edges, all tiles keep one size.
    @Test func foldSplitsColumnsWithoutTouchingIt() {
        for columns in 2...8 {
            let fold: ClosedRange<CGFloat> = 370...430
            guard let (size, split) = GridMetrics.split(count: columns, length: 800, spacing: 10, avoiding: fold) else {
                Issue.record("No split for \(columns) columns"); continue
            }
            let origins = GridMetrics.origins(count: columns, size: size, spacing: 10, split: split)
            #expect(origins.count == columns)
            #expect(origins.first == 0)
            #expect(abs(origins.last! + size - 800) < 0.01, "The last tile ends at the edge")
            for x in origins {
                #expect(x + size <= fold.lowerBound + 0.01 || x >= fold.upperBound - 0.01, "\(columns) columns: a tile at \(x) touches the fold")
            }
        }
    }

    /// An even board splits in the middle. An odd one puts the extra column on one side.
    @Test func foldSplitsNearTheMiddle() {
        let even = GridMetrics.split(count: 4, length: 800, spacing: 10, avoiding: 380...420)
        #expect(even?.split.after == 2)
        #expect(abs((even?.size ?? 0) - 185) < 0.01)
        let odd = GridMetrics.split(count: 5, length: 800, spacing: 10, avoiding: 380...420)
        #expect(odd?.split.after == 2 || odd?.split.after == 3)
    }

    /// Nothing to split: one column, or a fold outside the grid.
    @Test func foldOutsideTheGridChangesNothing() {
        #expect(GridMetrics.split(count: 1, length: 800, spacing: 10, avoiding: 380...420) == nil)
        #expect(GridMetrics.split(count: 4, length: 800, spacing: 10, avoiding: -10...20) == nil)
        #expect(GridMetrics.split(count: 4, length: 800, spacing: 10, avoiding: 790...820) == nil)
        let size = CGSize(width: 800, height: 600)
        let plain = GridMetrics.layout(in: size, rows: 4, columns: 4, spacing: 10)
        let missed = GridMetrics.layout(in: size, rows: 4, columns: 4, spacing: 10, fold: CGRect(x: 900, y: 0, width: 40, height: 600))
        #expect(plain == missed)
    }

    /// A fold running top to bottom splits the columns and keeps the rows as they are.
    @Test func uprightFoldSplitsColumnsInTheLayout() {
        let size = CGSize(width: 800, height: 600)
        let layout = GridMetrics.layout(in: size, rows: 4, columns: 4, spacing: 10, fold: CGRect(x: 380, y: -50, width: 40, height: 700))
        #expect(layout.columnSplit?.after == 2)
        #expect(layout.rowSplit == nil)
        #expect(layout.gap(beforeColumn: 2) > 0 && layout.gap(beforeColumn: 1) == 0)
        #expect(abs(layout.tileWidth * 4 + 30 + layout.gap(beforeColumn: 2) - 800) < 0.01)
    }

    /// A fold running side to side splits the rows of a board that fits, but not of one that scrolls.
    @Test func sidewaysFoldSplitsRowsOnlyWhenTheBoardFits() {
        let size = CGSize(width: 800, height: 600)
        let fold = CGRect(x: 0, y: 280, width: 800, height: 40)
        let fits = GridMetrics.layout(in: size, rows: 4, columns: 4, spacing: 10, fold: fold)
        #expect(!fits.scrolls)
        #expect(fits.rowSplit?.after == 2)
        #expect(fits.columnSplit == nil)
        let tall = GridMetrics.layout(in: size, rows: 12, columns: 4, spacing: 10, fold: fold)
        #expect(tall.scrolls)
        #expect(tall.rowSplit == nil)
    }
}
