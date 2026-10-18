// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

#if os(iOS)
/// A parent adds a photo to a tile and Hum offers names for it. A fake stands in for Vision
/// (-fakeObjectNames): the first photo is a dog, the next has long names. iOS only: it pastes through
/// UIPasteboard (on the Mac, the same editor code runs for Choose file…).
final class PhotoNamesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: a tap on a name fills the words, the parent's own phrase stays, a new photo brings new
    /// names, removing the photo hides them, and Cancel saves nothing.
    @MainActor
    func testNamesFromAPhoto() {
        let app = launchHum(["-skipFirstRun", "-startInParent", "-fakeObjectNames"])
        el(app, "emptySlot.3.3").tap()
        let phrase = el(app, "spokenTextField"), label = el(app, "labelField")
        XCTAssertTrue(phrase.waitForExistence(timeout: 3))

        pastePhoto(app)
        XCTAssertTrue(app.buttons["dog"].waitForExistence(timeout: 5), "A new photo gets names")
        XCTAssertEqual(ideas(app).count, 3)
        XCTAssertFalse(app.buttons["animal"].exists, "Broad groups are left out")
        keepScreenshot(app, "Names for the first photo")

        app.buttons["dog"].tap()
        XCTAssertEqual(phrase.value as? String, "dog")
        XCTAssertEqual(label.value as? String, "dog")
        // The phrase was only an earlier name, so it follows the new one.
        app.buttons["food bowl"].tap()
        XCTAssertEqual(phrase.value as? String, "food bowl")
        // Once the parent adds their own words, a name only changes the label.
        phrase.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        phrase.typeText(" please")
        // Compared with itself: the simulator keyboard sometimes adds a letter while typing.
        let ownWords = phrase.value as? String
        XCTAssertNotEqual(ownWords, "food bowl")
        app.buttons["leash"].tap()
        XCTAssertEqual(phrase.value as? String, ownWords)
        XCTAssertEqual(label.value as? String, "leash")

        pastePhoto(app)
        let balloon = app.buttons["hot air balloon"]
        XCTAssertTrue(balloon.waitForExistence(timeout: 5), "Another photo brings its own names")
        XCTAssertFalse(app.buttons["dog"].exists)
        keepScreenshot(app, "Long names")
        let window = app.windows.firstMatch.frame
        let names = ideas(app).allElementsBoundByIndex
        XCTAssertEqual(names.count, 3)
        for idea in names {
            XCTAssertTrue(window.contains(idea.frame), "“\(idea.label)” fits on screen")
        }
        XCTAssertEqual(Set(names.map { Int($0.frame.height.rounded()) }).count, 1, "No name wraps onto two lines")

        app.buttons["Remove photo"].firstMatch.tap()
        XCTAssertFalse(balloon.waitForExistence(timeout: 1), "No photo, no names")

        app.buttons["Cancel"].firstMatch.tap()
        dialogButton(app, "Discard changes").tap()
        XCTAssertTrue(el(app, "emptySlot.3.3").waitForExistence(timeout: 3), "Cancel saves nothing")
    }

    /// Scenario: Save puts the named tile in the spot the parent tapped. Nothing else moves.
    @MainActor
    func testSavedPhotoTileTakesTheTappedSpot() {
        let app = launchHum(["-skipFirstRun", "-startInParent", "-fakeObjectNames"])
        let neighbor = el(app, "editTile.play")
        XCTAssertTrue(neighbor.waitForExistence(timeout: 5))
        let neighborSpot = neighbor.frame, spot = el(app, "emptySlot.3.3").frame
        el(app, "emptySlot.3.3").tap()
        XCTAssertTrue(el(app, "spokenTextField").waitForExistence(timeout: 3))
        pastePhoto(app)
        XCTAssertTrue(app.buttons["dog"].waitForExistence(timeout: 5))
        app.buttons["dog"].tap()
        el(app, "saveTile").tap()

        let tile = el(app, "editTile.dog")
        XCTAssertTrue(tile.waitForExistence(timeout: 3))
        XCTAssertEqual(tile.frame, spot, "The new tile is in the spot the parent tapped")
        XCTAssertEqual(neighbor.frame, neighborSpot, "Other tiles stay where they are")
    }

    private func ideas(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "tileEditor.objectIdea")
    }

    /// Puts a picture on the clipboard and taps the editor's Paste button.
    private func pastePhoto(_ app: XCUIApplication) {
        UIPasteboard.general.image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        }
        let paste = app.buttons["Paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 3))
        paste.tap()
    }

    private func keepScreenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
#endif
