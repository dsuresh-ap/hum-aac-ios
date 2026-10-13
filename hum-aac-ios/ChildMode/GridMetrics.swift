// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics

/// How a board's fixed rows × columns fill the space it gets.
///
/// Columns always fill the width, so tiles never reflow sideways. Rows fill the height when they fit.
/// When they don't, the board scrolls down instead of squashing tiles. Every tile keeps its row and column.
enum GridMetrics {
    /// The smallest a tile gets, in either direction (the spec's minimum hit target).
    static let minimumTile: CGFloat = 88
    /// Tiles can be wider than tall, down to this height ÷ width. Flatter than this, the board scrolls.
    static let flattest: CGFloat = 0.4
    /// The shape tiles get on a board that scrolls (height ÷ width).
    static let scrollingShape: CGFloat = 0.75
    /// How much of the next row shows at the bottom of a scrolling board, so it's clear there's more.
    static let peek: CGFloat = 0.35

    struct Layout: Equatable {
        var tileWidth: CGFloat
        var tileHeight: CGFloat
        var scrolls: Bool
    }

    static func layout(in size: CGSize, rows: Int, columns: Int, spacing: CGFloat, canScroll: Bool = true) -> Layout {
        let width = max(tileWidth(across: size.width, columns: columns, spacing: spacing), 0)
        let fit = max((size.height - spacing * CGFloat(rows - 1)) / CGFloat(max(rows, 1)), 0)
        let shortest = max(minimumTile, width * flattest)
        guard canScroll, fit < shortest else { return Layout(tileWidth: width, tileHeight: fit, scrolls: false) }

        // Show as many whole rows as fit at a comfortable shape, plus a peek of the next one.
        let comfortable = max(shortest, width * scrollingShape)
        let whole = max(1, Int((size.height + spacing) / (comfortable + spacing)))
        let height = (size.height - spacing * CGFloat(whole)) / (CGFloat(whole) + peek)
        return Layout(tileWidth: width, tileHeight: max(height, shortest), scrolls: true)
    }

    static func tileWidth(across width: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(max(columns, 1))
    }

    /// The most columns that keep tiles at least `minimumTile` wide (1...8).
    static func maxColumns(across width: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0 else { return 8 }
        return min(max(Int((width + spacing) / (minimumTile + spacing)), 1), 8)
    }

    /// How many rows show at once on a board this size (the rest are reached by scrolling).
    static func visibleRows(in size: CGSize, rows: Int, columns: Int, spacing: CGFloat) -> Int {
        let layout = layout(in: size, rows: rows, columns: columns, spacing: spacing)
        guard layout.scrolls else { return rows }
        return min(rows, max(1, Int((size.height + spacing) / (layout.tileHeight + spacing))))
    }
}
