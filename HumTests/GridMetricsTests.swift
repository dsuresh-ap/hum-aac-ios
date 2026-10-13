// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

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
}
