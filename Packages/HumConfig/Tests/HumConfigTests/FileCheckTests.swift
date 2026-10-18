// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import HumConfig

/// A file with two boards (Home and Food); tests change the parts they need.
private func twoBoards(home: String = #""isHome": true"#, food: String = #""isHome": false"#,
                       foodID: String = "44444444-4444-4444-4444-444444444444",
                       foodSize: String = #""rows": 1, "columns": 2"#, homeTiles: String = "") -> Data {
    json("""
    {"formatVersion": 1, "boards": [
      {"id": "11111111-1111-1111-1111-111111111111", "name": "Home", "rows": 2, "columns": 2, \(home), "tiles": [\(homeTiles)]},
      {"id": "\(foodID)", "name": "Food", \(foodSize), \(food), "tiles": []}]}
    """)
}

/// The checks on a whole file that the schema can't make, and what a parent reads about them.
@Suite("Whole-file checks")
struct FileCheckTests {
    @Test func onlyOneHome() {
        let issues = HumConfigLoader.validate(twoBoards(food: #""isHome": true"#))
        #expect(issues.contains { $0.severity == .error && $0.problem == .severalHomes(["Home", "Food"]) })
        #expect(issues.contains { $0.message == "More than one board is marked as Home ('Home', 'Food'). Only one can be Home." })
    }

    @Test func everyBoardHasItsOwnID() {
        let issues = HumConfigLoader.validate(twoBoards(foodID: "11111111-1111-1111-1111-111111111111"))
        #expect(issues.contains { $0.severity == .error && $0.problem == .duplicateBoardID(.board("Food")) && $0.path == "/boards/1/id" })
    }

    @Test func aOneTileBoardIsTooSmall() {
        let issues = HumConfigLoader.validate(twoBoards(foodSize: #""rows": 1, "columns": 1"#))
        #expect(issues.contains { $0.severity == .error && $0.message == "Board 'Food' is too small. The smallest grid is 1 × 2." })
    }

    @Test func aSilentFolderNeedsALabel() {
        let issues = HumConfigLoader.validate(twoBoards(homeTiles: """
            {"id": "22222222-2222-2222-2222-222222222222", "spokenText": "", "row": 0, "column": 0,
             "linkedBoardID": "44444444-4444-4444-4444-444444444444"}
            """))
        #expect(issues.contains { $0.severity == .error && $0.problem == .folderNeedsLabel(board: .board("Home")) })
    }

    /// A one-board export may link to boards that are only in the full setup: it still opens.
    @Test func aLinkToAMissingBoardIsOnlyAWarning() throws {
        let loaded = try HumConfigLoader.load(twoBoards(homeTiles: """
            {"id": "22222222-2222-2222-2222-222222222222", "label": "toys", "spokenText": "Let's play", "row": 0, "column": 0,
             "linkedBoardID": "99999999-9999-9999-9999-999999999999"}
            """))
        #expect(loaded.warnings.map(\.problem) == [.missingLink(.tile("toys"))])
    }

    @Test func aPictureMissingFromThePackageIsOnlyAWarning() throws {
        let document = try HumConfigLoader.load(twoBoards(homeTiles: """
            {"id": "22222222-2222-2222-2222-222222222222", "label": "dog", "spokenText": "Dog!", "row": 0, "column": 0,
             "image": "media/dog.jpg"}
            """)).document
        let loaded = try HumConfigLoader.load(ZipArchive.write([.init(path: "hum.json", data: try document.encodedJSON())]))
        #expect(loaded.warnings.map(\.problem) == [.missingMedia(tile: "dog", path: "media/dog.jpg")])
    }

    // MARK: Schema problems in a parent's words

    func messages(tile: String) -> [String] {
        HumConfigLoader.validate(doc(tile: tile)).map(\.message)
    }

    @Test func schemaProblemsReadPlainly() {
        let id = #""id": "22222222-2222-2222-2222-222222222222""#
        #expect(messages(tile: #"{\#(id), "label": "a", "spokenText": "a", "row": "two", "column": 0}"#)
            .contains("Tile 'a': 'row' should be a whole number."))
        #expect(messages(tile: #"{\#(id), "label": "a", "spokenText": "a", "row": 0, "column": 0, "function": "shout"}"#)
            .contains("Tile 'a': 'function' must be one of: protest, request, connection, comment, regulation, other."))
        #expect(messages(tile: #"{\#(id), "label": "a", "spokenText": "a", "row": 0, "column": 0, "color": "red"}"#)
            .contains("Tile 'a': 'color' should look like #A1B2C3."))
        #expect(messages(tile: #"{\#(id), "label": "a", "spokenText": "a", "row": 0, "column": 0, "image": "pics/a.jpg"}"#)
            .contains("Tile 'a': 'image' has the wrong format."))
        #expect(messages(tile: #"{\#(id), "label": "a", "spokenText": "a", "row": -1, "column": 0}"#)
            .contains("Tile 'a': 'row' must be between 0 and 19."))
        #expect(messages(tile: #"{\#(id), "label": "\#(String(repeating: "a", count: 61))", "spokenText": "a", "row": 0, "column": 0}"#)
            .contains { $0.hasSuffix("'label' is too long (at most 60 characters).") })
        #expect(messages(tile: #"{"id": "not-a-uuid", "label": "a", "spokenText": "a", "row": 0, "column": 0}"#)
            .contains("Tile 'a': 'id' is not a valid ID. It should be a UUID like 3F2504E0-4F89-11D3-9A0C-0305E82C3301."))
    }

    @Test func boardAndSettingsProblemsNameWhatTheyAreAbout() {
        let issues = HumConfigLoader.validate(json("""
            {"formatVersion": 1, "settings": {"voice": {"rate": 3}, "appearance": "neon"},
             "boards": [{"id": "11111111-1111-1111-1111-111111111111", "name": "Home", "rows": 0, "columns": 2, "tiles": []}]}
            """)).map(\.message)
        #expect(issues.contains("Board 'Home': 'rows' must be between 1 and 20."))
        #expect(issues.contains("Settings: 'rate' must be between 0 and 1."))
        #expect(issues.contains("Settings: 'appearance' must be one of: system, light, dark."))
    }

    // MARK: The error as a whole

    @Test func manyProblemsAreSummed() {
        let issues = (1...7).map { ValidationIssue(.error, .noWords(.tile("t\($0)"))) } + [ValidationIssue(.warning, .missingLink(.tile("w")))]
        let text = HumConfigError.invalid(issues).errorDescription ?? ""
        #expect(text.hasPrefix("This setup has some problems:\nTile 't1' has no words to say."))
        #expect(text.contains("Tile 't5'") && !text.contains("Tile 't6'"))
        #expect(text.hasSuffix("…and 2 more."), "warnings aren't counted")
        #expect(!text.contains("Tile 'w'"))
    }

    @Test func issuesDescribeThemselvesForAgents() {
        #expect(ValidationIssue(.error, .noWords(.tile("a")), path: "/boards/0/tiles/0").description
            == "error: Tile 'a' has no words to say. [/boards/0/tiles/0]")
        #expect(ValidationIssue(.warning, "Something.").description == "warning: Something.")
        #expect(HumConfigError.newerFormat(found: 2, supported: 1).errorDescription
            == "This setup was made with a newer version of Hum. Please update Hum to open it.")
    }
}
