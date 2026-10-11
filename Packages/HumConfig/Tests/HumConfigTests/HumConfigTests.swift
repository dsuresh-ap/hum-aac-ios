// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import HumConfig

/// Repo root, found from this file's location (Packages/HumConfig/Tests/HumConfigTests/…).
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

func example(_ name: String) throws -> Data {
    try Data(contentsOf: repoRoot.appendingPathComponent("examples/\(name)"))
}

func json(_ string: String) -> Data { Data(string.utf8) }

/// A minimal valid document with one tile; tests mutate the tile JSON.
func doc(tile: String, rows: Int = 2, columns: Int = 2) -> Data {
    json("""
    {"formatVersion": 1, "boards": [{"id": "11111111-1111-1111-1111-111111111111", "name": "Home",
      "rows": \(rows), "columns": \(columns), "isHome": true, "tiles": [\(tile)]}]}
    """)
}

@Suite("Examples & golden files")
struct ExampleTests {
    static let names = ["starter.hum.json", "food.hum.json", "linked-boards.hum.json"]

    @Test(arguments: names)
    func exampleLoadsWithoutErrors(name: String) throws {
        let loaded = try HumConfigLoader.load(try example(name))
        #expect(!loaded.document.boards.isEmpty)
        #expect(loaded.warnings.filter { $0.severity == .error }.isEmpty)
    }

    /// Golden test: import → export gives back equal JSON.
    @Test(arguments: names)
    func exampleRoundTripsToEqualJSON(name: String) throws {
        let original = try example(name)
        let loaded = try HumConfigLoader.load(original)
        let reencoded = try loaded.document.encodedJSON()
        #expect(try JSONValue.parse(reencoded) == JSONValue.parse(original))
    }

    @Test func starterHasProtestTilesOnHomeAndFits() throws {
        let doc = try HumConfigLoader.load(try example("starter.hum.json")).document
        let home = try #require(doc.homeBoard)
        let spoken = Set(home.tiles.map(\.spokenText))
        for phrase in ["No thank you", "Stop!", "All done", "I need a break", "Too loud", "Help me"] {
            #expect(spoken.contains(phrase))
        }
        #expect(home.tiles.count == 18)
    }

    @Test func bundledSchemaMatchesRepoSchema() throws {
        let repo = try Data(contentsOf: repoRoot.appendingPathComponent("schema/hum.schema.json"))
        let bundled = try Data(contentsOf: try #require(Bundle.module.url(forResource: "hum.schema", withExtension: "json")))
        #expect(repo == bundled, "Copy schema/hum.schema.json to Packages/HumConfig/Sources/HumConfig/Resources/")
    }

    @Test func schemaUsesOnlySupportedKeywords() throws {
        let schema = try JSONValue.parse(try Data(contentsOf: repoRoot.appendingPathComponent("schema/hum.schema.json")))
        var unsupported: Set<String> = []
        func walk(_ v: JSONValue, isPropertyMap: Bool) {
            guard case .object(let dict) = v else { return }
            for (key, child) in dict {
                if !isPropertyMap, !SchemaValidator.supportedKeywords.contains(key) { unsupported.insert(key) }
                // Children of "properties" and "$defs" are names, not keywords.
                let childIsMap = !isPropertyMap && (key == "properties" || key == "$defs")
                if childIsMap { walk(child, isPropertyMap: true) } else { walk(child, isPropertyMap: false) }
            }
        }
        walk(schema, isPropertyMap: false)
        #expect(unsupported.isEmpty, "Schema uses keywords the validator ignores: \(unsupported)")
    }
}

@Suite("Validation")
struct ValidationTests {
    @Test func friendlyMessageForEmptySpokenText() {
        let issues = HumConfigLoader.validate(doc(tile: """
            {"id": "22222222-2222-2222-2222-222222222222", "label": "snack", "spokenText": "  ", "row": 0, "column": 0}
            """))
        #expect(issues.contains { $0.message == "Tile 'snack' has no words to say." })
    }

    @Test func friendlyMessageForMissingSpokenText() {
        let issues = HumConfigLoader.validate(doc(tile: """
            {"id": "22222222-2222-2222-2222-222222222222", "label": "snack", "row": 0, "column": 0}
            """))
        #expect(issues.contains { $0.message == "Tile 'snack' has no words to say." })
    }

    @Test func newerFormatIsRefusedClearly() {
        #expect(throws: HumConfigError.newerFormat(found: 99, supported: 1)) {
            try HumConfigLoader.load(json(#"{"formatVersion": 99, "boards": []}"#))
        }
    }

    @Test func garbageNeverCrashes() {
        for input in ["", "nope", "[]", "{}", #"{"formatVersion": "1"}"#, "PK\u{3}\u{4}garbage"] {
            #expect(!HumConfigLoader.validate(json(input)).isEmpty)
        }
    }

    @Test func tileOutsideGridIsAnError() {
        let issues = HumConfigLoader.validate(doc(tile: """
            {"id": "22222222-2222-2222-2222-222222222222", "label": "x", "spokenText": "x", "row": 5, "column": 0}
            """))
        #expect(issues.contains { $0.severity == .error && $0.message.contains("outside the grid") })
    }

    @Test func twoTilesInOneSpotIsAnError() {
        let issues = HumConfigLoader.validate(doc(tile: """
            {"id": "22222222-2222-2222-2222-222222222222", "label": "a", "spokenText": "a", "row": 0, "column": 0},
            {"id": "33333333-3333-3333-3333-333333333333", "label": "b", "spokenText": "b", "row": 0, "column": 0}
            """))
        #expect(issues.contains { $0.severity == .error && $0.message.contains("same spot") })
    }

    @Test func duplicateTileIDIsAnError() {
        let issues = HumConfigLoader.validate(doc(tile: """
            {"id": "22222222-2222-2222-2222-222222222222", "label": "a", "spokenText": "a", "row": 0, "column": 0},
            {"id": "22222222-2222-2222-2222-222222222222", "label": "b", "spokenText": "b", "row": 0, "column": 1}
            """))
        #expect(issues.contains { $0.severity == .error && $0.message.contains("same ID") })
    }

    @Test func praisePhraseIsWarned() throws {
        let loaded = try HumConfigLoader.load(doc(tile: """
            {"id": "22222222-2222-2222-2222-222222222222", "label": "yay", "spokenText": "Good job!", "row": 0, "column": 0}
            """))
        #expect(loaded.warnings.contains { $0.message.contains("good job") })
    }

    @Test func unknownFieldsAreKept() throws {
        let input = doc(tile: """
            {"id": "22222222-2222-2222-2222-222222222222", "label": "a", "spokenText": "a", "row": 0, "column": 0,
             "futureField": {"nested": [1, 2, true]}}
            """)
        let loaded = try HumConfigLoader.load(input)
        #expect(loaded.document.boards[0].tiles[0].extra["futureField"] != nil)
        #expect(try JSONValue.parse(loaded.document.encodedJSON()) == JSONValue.parse(input))
    }

    @Test func protestOnlyOnSubBoardIsWarned() throws {
        let input = json("""
        {"formatVersion": 1, "boards": [
          {"id": "11111111-1111-1111-1111-111111111111", "name": "Home", "rows": 1, "columns": 2, "isHome": true, "tiles": []},
          {"id": "44444444-4444-4444-4444-444444444444", "name": "Sub", "rows": 1, "columns": 2, "tiles": [
            {"id": "22222222-2222-2222-2222-222222222222", "label": "stop", "spokenText": "Stop!", "row": 0, "column": 0, "function": "protest"}]}]}
        """)
        let loaded = try HumConfigLoader.load(input)
        #expect(loaded.warnings.contains { $0.message.contains("should also be on Home") })
    }
}

@Suite("Zip & packages")
struct ZipTests {
    @Test func zipRoundTrip() throws {
        let entries = [
            ZipArchive.Entry(path: "hum.json", data: json("{}")),
            ZipArchive.Entry(path: "media/a.jpg", data: Data((0..<5000).map { UInt8($0 % 251) })),
        ]
        #expect(try ZipArchive.read(ZipArchive.write(entries)) == entries)
    }

    @Test func crc32KnownValue() {
        #expect(CRC32.checksum(json("The quick brown fox jumps over the lazy dog")) == 1_095_738_169)
    }

    @Test func pureSwiftInflateFixedHuffman() throws {
        let raw = try #require(Data(base64Encoded: "y0jNyclXyEAnAQ=="))
        #expect(try Inflate.decompress(raw) == json("hello hello hello hello"))
    }

    @Test func pureSwiftInflateDynamicHuffman() throws {
        let raw = try #require(Data(base64Encoded: "tdbLDYNADIThVoZ7hGI7zxIicUwKWNhFrEC7EqBEdJ8mPA38J38ad2nfMIVvwrCGYU7r1uCFklJEQL+mMLd4V+Qy5pL3A6FE9OmoJTb4TKjTCXnHmJYFsf5KizM676T4J9U/af7Ji3/y6p+8+Sfv/smHf/JJOHUGH4IfIQASgiAhEBKCISEgEoIiITASgiMlOFLGDhEcKcGREhwpwZESHCnBkRIcKcGRERwZwZExHjqCIyM4MoIjIzgygiMjOLLnHw=="))
        let text = (0..<40).map { "Lets have crackers! I need a break. To infinity and beyond! Uh oh, it fell down. \($0)" }.joined(separator: " ")
        #expect(try Inflate.decompress(raw) == json(text))
    }

    @Test func corruptDeflateThrows() {
        #expect(throws: (any Error).self) { try Inflate.decompress(Data([0xFF, 0xFF, 0xFF])) }
    }

    @Test func packageRoundTripWithMedia() throws {
        var document = try HumConfigLoader.load(try example("starter.hum.json")).document
        document.boards[0].tiles[0].image = "media/hi.jpg"
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        let packed = try HumPackage.write(document, media: ["media/hi.jpg": jpeg, "media/unused.jpg": jpeg])
        let loaded = try HumConfigLoader.load(packed)
        #expect(loaded.document == document)
        #expect(loaded.media == ["media/hi.jpg": jpeg])  // unreferenced media is not exported
        #expect(loaded.warnings.isEmpty)
    }

    @Test func unsafePathsAreRejected() {
        for path in ["../evil", "/etc/passwd", "media/../../x", "C:\\x", "media\\x"] {
            #expect(!HumPackage.isSafe(path))
        }
        #expect(HumPackage.isSafe("media/photo 1.jpg"))
    }

    @Test func zipWithoutHumJSONIsFriendlyError() {
        let zip = ZipArchive.write([.init(path: "other.txt", data: json("x"))])
        #expect(throws: HumConfigError.badPackage("It has no hum.json inside.")) { try HumConfigLoader.load(zip) }
    }
}

@Suite("GLP rules")
struct GLPRuleTests {
    @Test func detectsPraiseAndCompliance() {
        #expect(GLPRules.discouragedPhrase(in: "GOOD JOB!!") == "good job")
        #expect(GLPRules.discouragedPhrase(in: "Quiet hands, please") == "quiet hands")
        #expect(GLPRules.discouragedPhrase(in: "Let's have a snack") == nil)
        // Whole words only: "tokens" in another word shouldn't match "token" by accident… but "token" alone does.
        #expect(GLPRules.discouragedPhrase(in: "I want the train tokenizer") == nil)
    }

    @Test func detectsSplitGestalts() {
        #expect(GLPRules.isFragment("get out", of: "Let's get out of here!"))
        #expect(GLPRules.isFragment("Let's", of: "Let's get out of here!"))
        #expect(!GLPRules.isFragment("Let's get out of here!", of: "let's get out of here"))
        #expect(!GLPRules.isFragment("all aboard", of: "Let's get out of here!"))
    }
}
