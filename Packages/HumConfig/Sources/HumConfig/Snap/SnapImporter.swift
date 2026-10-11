// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Converts a TD Snap page set (`.sps`, a SQLite file) into a Hum setup.
///
/// - Every page reachable from Snap's Home through folder buttons becomes a board, and each button
///   keeps its row and column. Snap's own Back and Home buttons are left out: Hum has its own.
/// - On topic pages whose left column only held Snap's navigation (Back, Next page, Home), that
///   column is removed and "Next page" moves to the bottom-right corner.
/// - Board and tile IDs are Snap's own IDs, so importing a newer export of the same page set
///   updates the tiles instead of adding copies.
/// - Snap's symbols (WMF/EMF) become SVG; photos are copied as they are. Symbols from Snap's
///   built-in library aren't saved in the file; those tiles get an emoji placeholder when one fits.
/// - Things Hum doesn't have (keyboards, the dashboard, word forms, grids over 8 × 8) are left out
///   and listed in `notes`.
public enum SnapImporter {
    public struct Result: Sendable {
        public var document: HumDocument
        /// Media files keyed by their path in the document, e.g. "media/sym806.svg".
        public var media: [String: Data]
        /// What was left out or changed, for the parent to read.
        public var notes: [String]
    }

    public enum ImportError: Error, LocalizedError, Equatable {
        case notSnapFile
        case damaged(String)

        public var errorDescription: String? {
            switch self {
            case .notSnapFile: "This isn't a TD Snap page set (.sps)."
            case .damaged(let detail): "This TD Snap page set couldn't be read (\(detail))."
            }
        }
    }

    /// Pages Hum can't show: Snap's keyboards, dashboard, word forms, toolbar and message bar.
    static let skippedTitleWords = ["keyboard", "dashboard", "eye gaze", "word forms", "tool bar", "message bar", "_template"]

    public static func convert(_ data: Data) throws -> Result {
        let db: SQLiteReader
        do { db = try SQLiteReader(data) } catch { throw ImportError.notSnapFile }
        guard ["Page", "PageLayout", "ElementPlacement", "ElementReference", "Button", "PageSetProperties"].allSatisfy(db.hasTable) else {
            throw ImportError.notSnapFile
        }
        do {
            return try Converter(db: db).run()
        } catch let error as SQLiteReader.Malformed {
            throw ImportError.damaged(error.description)
        }
    }
}

// MARK: - Conversion

private struct Converter {
    let db: SQLiteReader

    struct Button {
        let row: SQLiteReader.Row
        let column: Int, gridRow: Int, span: (Int, Int), visible: Bool, background: Int?
        let commands: [String]
        let link: UUID?
        var label: String { (row["Label"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        var message: String { (row["Message"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        var speaks: Bool { commands.contains("3") }
        /// Snap's Back ("4") and Home ("5") commands.
        var isBackOrHome: Bool { commands.contains("4") || commands.contains("5") }
    }

    func run() throws -> SnapImporter.Result {
        var notes = Notes()
        let props = try db.rows("PageSetProperties").first
        let pageRows = try db.rows("Page")
        var pages: [UUID: SQLiteReader.Row] = [:]
        for page in pageRows { if let id = uuid(page["UniqueId"]) { pages[id] = page } }
        guard let homeID = props.flatMap({ uuid($0["DefaultHomePageUniqueId"]) }), pages[homeID] != nil else {
            throw SnapImporter.ImportError.damaged("it has no Home page")
        }

        // Index the tables the pages are built from.
        let layoutsByPage = Dictionary(grouping: try db.rows("PageLayout"), by: { $0["PageId"].int ?? -1 })
        let placementsByLayout = Dictionary(grouping: try db.rows("ElementPlacement"), by: { $0["PageLayoutId"].int ?? -1 })
        var references: [Int: SQLiteReader.Row] = [:]
        for ref in try db.rows("ElementReference") { references[Int(ref.rowid)] = ref }
        var buttonsByReference: [Int: SQLiteReader.Row] = [:]
        for button in try db.rows("Button") { if let ref = button["ElementReferenceId"].int { buttonsByReference[ref] = button } }
        var links: [Int: UUID] = [:]
        if db.hasTable("ButtonPageLink") {
            for link in try db.rows("ButtonPageLink") { if let b = link["ButtonId"].int, let id = uuid(link["PageUniqueId"]) { links[b] = id } }
        }
        var commands: [Int: [String]] = [:]
        if db.hasTable("CommandSequence") {
            for seq in try db.rows("CommandSequence") {
                if let b = seq["ButtonId"].int { commands[b] = Self.commandTypes(seq["SerializedCommands"].string) }
            }
        }
        let gridDimension = props?["GridDimension"].string ?? ""
        let mainColumns = Int(gridDimension.split(separator: ",").first ?? "") ?? 1

        func layout(for page: SQLiteReader.Row) -> SQLiteReader.Row? {
            let layouts = layoutsByPage[Int(page.rowid)] ?? []
            let preferred = layouts.filter { ($0["PageLayoutSetting"].string ?? "").hasPrefix(gridDimension + ",") }
            if let best = preferred.first(where: { ($0["PageLayoutSetting"].string ?? "").contains("True") }) ?? preferred.first { return best }
            return layouts.max { (placementsByLayout[Int($0.rowid)]?.count ?? 0) < (placementsByLayout[Int($1.rowid)]?.count ?? 0) }
        }
        func isMainLayout(_ layout: SQLiteReader.Row?) -> Bool {
            (layout?["PageLayoutSetting"].string ?? "").hasPrefix(gridDimension + ",")
        }
        func buttons(on page: SQLiteReader.Row, layout: SQLiteReader.Row?) -> [Button] {
            guard let layout else { return [] }
            return (placementsByLayout[Int(layout.rowid)] ?? []).compactMap { placement in
                guard let refID = placement["ElementReferenceId"].int, let ref = references[refID],
                      ref["PageId"].int == Int(page.rowid), let button = buttonsByReference[refID],
                      let position = Self.pair(placement["GridPosition"].string) else { return nil }
                return Button(row: button, column: position.0, gridRow: position.1,
                              span: Self.pair(placement["GridSpan"].string) ?? (1, 1),
                              visible: placement["Visible"].int != 0, background: ref["BackgroundColor"].int,
                              commands: commands[Int(button.rowid)] ?? [], link: links[Int(button.rowid)])
            }
        }
        func includable(_ id: UUID) -> Bool {
            guard let page = pages[id], page["PageType"].int == 1 else { return false }
            let title = (page["Title"].string ?? "").lowercased()
            return !SnapImporter.skippedTitleWords.contains { title.contains($0) }
        }

        // Walk every page reachable from Home through folder buttons.
        var order: [UUID] = [homeID]
        var seen: Set<UUID> = [homeID]
        var index = 0
        while index < order.count {
            let page = pages[order[index]]!
            index += 1
            for button in buttons(on: page, layout: layout(for: page)) where button.commands.contains("2") {
                guard let link = button.link, !seen.contains(link) else { continue }
                seen.insert(link)
                if includable(link) { order.append(link) }
            }
        }
        let included = Set(order)

        // Every Express-style board gets at least as many rows as Home uses, so tiles stay one size.
        let homePage = pages[homeID]!
        let homeLayout = layout(for: homePage)
        let homeRows = buttons(on: homePage, layout: homeLayout).map { $0.gridRow + $0.span.1 }.max() ?? 1

        var boards: [HumBoard] = []
        var usedTileIDs: Set<UUID> = []
        var media: [String: Data] = [:]
        var mediaPathByImage: [Int: String?] = [:]

        func picture(for button: Button) throws -> String? {
            let imageID = button.row["PageSetImageId"].int ?? 0
            guard imageID > 0 else {
                if (button.row["LibrarySymbolId"].int ?? 0) > 0 { notes.add(.librarySymbol, button.label) }
                return nil
            }
            if let done = mediaPathByImage[imageID] { return done }
            var path: String?
            if let bytes = try db.row("PageSetData", rowid: Int64(imageID))?["Data"].bytes {
                if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
                    path = "media/img\(imageID).jpg"
                    media[path!] = Data(bytes)
                } else if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                    path = "media/img\(imageID).png"
                    media[path!] = Data(bytes)
                } else if let svg = MetafileSVG.svg(from: bytes) {
                    path = "media/\(bytes.first == 0xD7 ? "sym" : "emf")\(imageID).svg"
                    media[path!] = Data(svg.utf8)
                } else {
                    notes.add(.unsupportedPicture, button.label)
                }
            }
            mediaPathByImage[imageID] = path
            return path
        }

        for pageID in order {
            let page = pages[pageID]!
            let title = (page["Title"].string ?? "Page").trimmingCharacters(in: .whitespacesAndNewlines)
            let pageLayout = layout(for: page)
            let main = isMainLayout(pageLayout) || pageID == homeID
            var tiles: [HumTile] = []
            var navigationColumn = false
            var nextPageTileIDs: Set<UUID> = []

            for button in buttons(on: page, layout: pageLayout) {
                if button.isBackOrHome || (button.link.map { pages[$0] == nil } ?? false) && !button.speaks {
                    if button.column == 0 { navigationColumn = true }
                    continue
                }
                let label = button.label
                let navigates = button.commands.contains("2") && button.link.map(included.contains) == true
                guard button.speaks || navigates else {
                    if !label.isEmpty, button.visible, button.row["ContentType"].int == 6 {
                        notes.add(button.commands.contains("2") ? .leftOutFolder : .noAction, "\(title): \(label)")
                    }
                    continue
                }
                if button.span != (1, 1) { notes.add(.span, "\(title): \(label)") }
                let spoken = button.speaks ? String((button.message.isEmpty ? label : button.message).prefix(500)) : ""
                var tileLabel = label.isEmpty ? spoken : label
                if tileLabel.isEmpty, navigates, let link = button.link { tileLabel = pages[link]?["Title"].string ?? "" }
                tileLabel = String(tileLabel.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tileLabel.isEmpty || !spoken.isEmpty else { continue }

                var id = uuid(button.row["UniqueId"]) ?? Self.stableUUID("\(pageID)/\(button.row.rowid)")
                if usedTileIDs.contains(id) { id = Self.stableUUID("\(pageID)/\(button.row.rowid)") }
                usedTileIDs.insert(id)
                let isNextPage = navigates && !button.speaks && button.column == 0 && label.lowercased().hasPrefix("next")
                if isNextPage { nextPageTileIDs.insert(id); navigationColumn = true }

                tiles.append(HumTile(
                    id: id, label: tileLabel.isEmpty ? spoken : tileLabel, spokenText: spoken,
                    row: button.gridRow, column: button.column,
                    function: button.speaks && title.lowercased().contains("protest") ? .protest : nil,
                    color: Self.hexColor(button.background),
                    linkedBoardID: navigates ? button.link : nil,
                    hidden: !button.visible,
                    image: try picture(for: button)))
            }

            var columns = max(tiles.map { $0.column + 1 }.max() ?? 1, 1)
            var rows = max(tiles.map { $0.row + 1 }.max() ?? 1, 1)
            if main {
                columns = max(columns, mainColumns)
                rows = max(rows, homeRows)
                // Snap's navigation column: Hum has its own Back and Home, so drop it.
                let onlyNavigation = tiles.allSatisfy { $0.column > 0 || nextPageTileIDs.contains($0.id) }
                if pageID != homeID, navigationColumn, onlyNavigation, columns > 1 {
                    columns -= 1
                    for i in tiles.indices where !nextPageTileIDs.contains(tiles[i].id) { tiles[i].column -= 1 }
                    for i in tiles.indices where nextPageTileIDs.contains(tiles[i].id) {
                        let taken = Set(tiles.filter { !nextPageTileIDs.contains($0.id) }.map { [$0.row, $0.column] })
                        if taken.contains([rows - 1, columns - 1]) { rows += 1 }
                        tiles[i].row = rows - 1
                        tiles[i].column = columns - 1
                    }
                }
            } else if !tiles.isEmpty {
                // Rating and pain scales: drop the empty rows and columns their big pictures used.
                let usedRows = Set(tiles.map(\.row)).sorted(), usedColumns = Set(tiles.map(\.column)).sorted()
                for i in tiles.indices {
                    tiles[i].row = usedRows.firstIndex(of: tiles[i].row)!
                    tiles[i].column = usedColumns.firstIndex(of: tiles[i].column)!
                }
                rows = usedRows.count
                columns = usedColumns.count
            }
            if columns > 8 || rows > 8 {
                notes.add(.tooBig, "\(title) (\(columns) × \(rows))")
                continue
            }
            if rows * columns < 2 { columns = 2 }
            boards.append(HumBoard(id: pageID, name: String((title.isEmpty ? "Page" : title).prefix(80)),
                                   rows: rows, columns: columns, isHome: pageID == homeID, tiles: tiles))
        }

        // Folders that open a board that was left out just speak instead.
        let kept = Set(boards.map(\.id))
        for b in boards.indices {
            for t in boards[b].tiles.indices {
                guard let link = boards[b].tiles[t].linkedBoardID, !kept.contains(link) else { continue }
                boards[b].tiles[t].linkedBoardID = nil
                if boards[b].tiles[t].spokenText.isEmpty { boards[b].tiles[t].spokenText = boards[b].tiles[t].label }
            }
        }
        // Emoji placeholders for tiles without a picture.
        for b in boards.indices {
            for t in boards[b].tiles.indices where boards[b].tiles[t].image == nil {
                let tile = boards[b].tiles[t]
                boards[b].tiles[t].symbol = EmojiSuggester.suggestion(label: tile.label, spokenText: tile.spokenText)
            }
        }

        let name = (props?["FriendlyName"].string).flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
        return SnapImporter.Result(document: HumDocument(name: name, boards: boards), media: media, notes: notes.lines)
    }

    // MARK: Helpers

    private func uuid(_ value: SQLiteReader.Value) -> UUID? {
        value.string.flatMap { UUID(uuidString: $0) }
    }

    /// "col,row" → (col, row)
    static func pair(_ text: String?) -> (Int, Int)? {
        let parts = (text ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    /// The "$type" of each command in Snap's serialized command list (2 = open page, 3 = speak, 4 = back, 5 = home).
    static func commandTypes(_ json: String?) -> [String] {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = object["$values"] as? [[String: Any]] else { return [] }
        return values.compactMap { $0["$type"] as? String }
    }

    /// Snap stores colors as signed ARGB. Fully transparent means "no color".
    static func hexColor(_ argb: Int?) -> String? {
        guard let argb else { return nil }
        let v = UInt32(truncatingIfNeeded: argb)
        guard v >> 24 != 0 else { return nil }
        return String(format: "#%06X", v & 0xFFFFFF)
    }

    /// A UUID derived from a string, the same on every run (FNV-1a, 128 bits).
    static func stableUUID(_ text: String) -> UUID {
        var a: UInt64 = 0xcbf2_9ce4_8422_2325, b: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in text.utf8 {
            a = (a ^ UInt64(byte)) &* 0x100_0000_01b3
            b = (b ^ UInt64(byte)) &* 0x100_0000_01b3 &+ 0x9e37_79b9
        }
        var bytes = withUnsafeBytes(of: a.bigEndian) { Array($0) } + withUnsafeBytes(of: b.bigEndian) { Array($0) }
        bytes[6] = (bytes[6] & 0x0F) | 0x80  // version 8 (custom)
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Collects what was left out, grouped, for one readable summary.
private struct Notes {
    enum Kind: CaseIterable {
        case librarySymbol, unsupportedPicture, noAction, leftOutFolder, span, tooBig

        var heading: String {
            switch self {
            case .librarySymbol: "Tiles whose Snap library symbol isn't saved in the file (no picture)"
            case .unsupportedPicture: "Tiles with a picture Hum can't read"
            case .noAction: "Buttons that do nothing in Snap, left out"
            case .leftOutFolder: "Folders to pages Hum can't show (keyboards, dashboard, …), left out"
            case .span: "Buttons that covered several cells, now one cell"
            case .tooBig: "Pages bigger than Hum's 8 × 8 grid, left out"
            }
        }
    }

    private var items: [Kind: [String]] = [:]

    mutating func add(_ kind: Kind, _ item: String) { items[kind, default: []].append(item) }

    var lines: [String] {
        Kind.allCases.compactMap { kind in
            guard let list = items[kind], !list.isEmpty else { return nil }
            var unique: [String] = []
            for item in list where !unique.contains(item) { unique.append(item) }
            let shown = unique.prefix(30).joined(separator: "; ") + (unique.count > 30 ? "; …" : "")
            return "\(kind.heading): \(list.count). \(shown)"
        }
    }
}
