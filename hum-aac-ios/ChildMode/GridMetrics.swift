// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics

/// How a board's fixed rows × columns fill the space it gets.
///
/// Columns always fill the width, so tiles never reflow sideways. Rows fill the height when they fit.
/// When they don't, the board scrolls down instead of squashing tiles. Every tile keeps its row and column.
/// On a folding iPhone held partly folded, the grid opens a gap where the screen folds, so no tile sits on it.
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
        /// Extra room between two columns, where the screen folds.
        var columnSplit: Split? = nil
        /// Extra room between two rows, where the screen folds (only on a board that doesn't scroll).
        var rowSplit: Split? = nil

        func gap(beforeColumn column: Int) -> CGFloat { columnSplit?.after == column ? columnSplit!.gap : 0 }
        func gap(beforeRow row: Int) -> CGFloat { rowSplit?.after == row ? rowSplit!.gap : 0 }
    }

    /// Extra room before tile `after` along one direction, on top of the usual spacing.
    struct Split: Equatable {
        var after: Int
        var gap: CGFloat
    }

    /// - Parameter fold: where the screen folds across the grid, with the system's margins for touch
    ///   targets, in the grid's own coordinates. Nil when nothing folds.
    static func layout(in size: CGSize, rows: Int, columns: Int, spacing: CGFloat, canScroll: Bool = true,
                       fold: CGRect? = nil) -> Layout {
        // A tall, thin fold runs top to bottom and splits the columns. A wide one splits the rows.
        let foldSplitsColumns = fold.map { $0.height >= $0.width } ?? false
        let columnFold = foldSplitsColumns ? fold.flatMap { split(count: columns, length: size.width, spacing: spacing, avoiding: $0.minX...$0.maxX) } : nil
        let width = columnFold?.size ?? max(tileWidth(across: size.width, columns: columns, spacing: spacing), 0)
        let fit = max((size.height - spacing * CGFloat(rows - 1)) / CGFloat(max(rows, 1)), 0)
        let shortest = max(minimumTile, width * flattest)
        guard canScroll, fit < shortest else {
            var layout = Layout(tileWidth: width, tileHeight: fit, scrolls: false, columnSplit: columnFold?.split)
            // Rows split only when the tiles stay tall enough. A scrolling board moves under the fold anyway.
            if let fold, !foldSplitsColumns,
               let rowFold = split(count: rows, length: size.height, spacing: spacing, avoiding: fold.minY...fold.maxY),
               !canScroll || rowFold.size >= shortest {
                layout.tileHeight = rowFold.size
                layout.rowSplit = rowFold.split
            }
            return layout
        }

        // Show as many whole rows as fit at a comfortable shape, plus a peek of the next one.
        let comfortable = max(shortest, width * scrollingShape)
        let whole = max(1, Int((size.height + spacing) / (comfortable + spacing)))
        let height = (size.height - spacing * CGFloat(whole)) / (CGFloat(whole) + peek)
        return Layout(tileWidth: width, tileHeight: max(height, shortest), scrolls: true, columnSplit: columnFold?.split)
    }

    /// Tiles of one size on both sides of a fold, so none sits on it. The first and last tiles stay at the
    /// edges and the spare room goes into the fold. Picks the split that keeps tiles biggest.
    /// Nil when there's nothing to split: one tile, or a fold that misses the inside of the grid.
    static func split(count: Int, length: CGFloat, spacing: CGFloat, avoiding fold: ClosedRange<CGFloat>) -> (size: CGFloat, split: Split)? {
        guard count > 1, fold.lowerBound > 0, fold.upperBound < length else { return nil }
        var best: (size: CGFloat, after: Int)?
        for after in 1..<count {
            let before = (fold.lowerBound - spacing * CGFloat(after - 1)) / CGFloat(after)
            let behind = (length - fold.upperBound - spacing * CGFloat(count - after - 1)) / CGFloat(count - after)
            let size = min(before, behind)
            if size > (best?.size ?? 0) { best = (size, after) }
        }
        guard let best else { return nil }
        let gap = length - best.size * CGFloat(count) - spacing * CGFloat(count - 1)
        return (best.size, Split(after: best.after, gap: gap))
    }

    /// Where each tile starts along one direction.
    static func origins(count: Int, size: CGFloat, spacing: CGFloat, split: Split?) -> [CGFloat] {
        (0..<count).map { i in
            CGFloat(i) * (size + spacing) + (split.map { i >= $0.after ? $0.gap : 0 } ?? 0)
        }
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
