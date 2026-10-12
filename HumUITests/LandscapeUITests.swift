// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

#if os(iOS)
/// iPhone in landscape: a phone page (4 × 8) is wide and short there.
/// The child's tiles put the picture beside the label; the editor scrolls instead of squeezing tiles.
final class LandscapeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// A full-screen screenshot (an app screenshot comes out rotated in landscape).
    @MainActor
    private func screen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scenario: a parent edits a big board with the phone sideways. Tiles keep a usable size and never
    /// overlap; the board scrolls to reach the rest.
    @MainActor
    func testEditorScrollsInsteadOfOverlappingTiles() throws {
        try XCTSkipIf(isPad, "iPhone only")
        // Home 6 columns wide: shown in pages of 4 × 8 on iPhone.
        let app = launchHum(["-skipFirstRun", "-startInParent", "-wideHome", "-phoneLayout"])
        XCTAssertTrue(el(app, "editTile.hi").waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(el(app, "editGridScroll").waitForExistence(timeout: 5), "The editor scrolls when the board doesn't fit")
        screen("editor landscape")
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'editTile.'")).allElementsBoundByIndex
            .filter { $0.isHittable }
        XCTAssertFalse(tiles.isEmpty)
        let frames = tiles.map(\.frame)
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.height, 71, "Edit tiles stay at least 72 pt tall")
        }
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] {
                XCTAssertFalse(a.insetBy(dx: 1, dy: 1).intersects(b.insetBy(dx: 1, dy: 1)), "Tiles never overlap")
            }
        }
    }

    /// Scenario: the child turns the phone sideways. Tiles keep their spots, and the history box steps
    /// aside so the rows keep their height.
    @MainActor
    func testChildBoardInLandscape() throws {
        try XCTSkipIf(isPad, "iPhone only")
        let app = launchHum(["-skipFirstRun", "-wideHome", "-phoneLayout", "-demoHistory"])
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 5))
        let portraitOrder = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile.'")).allElementsBoundByIndex
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }.map(\.identifier)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Said: Hi! Say it again."].waitForNonExistence(timeout: 5), "No history box in iPhone landscape")
        screen("child landscape")
        let landscapeOrder = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tile.'")).allElementsBoundByIndex
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }.map(\.identifier)
        XCTAssertEqual(landscapeOrder, portraitOrder, "Every tile keeps its spot when the phone turns")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Said: Hi! Say it again."].waitForExistence(timeout: 5), "The history box comes back in portrait")
    }
}
#endif
