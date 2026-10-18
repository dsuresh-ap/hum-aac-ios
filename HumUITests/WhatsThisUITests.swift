// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// The child's "What's this?" camera. The simulator has no camera, so a still picture stands in
/// (-fakeCamera) and a fake guesses the words (-fakeObjectNames): first dog, then long names, then nothing.
final class WhatsThisUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: the setting is off (the default), so the child's board has no camera button.
    @MainActor
    func testNoButtonWhenOff() {
        let app = launchHum(["-skipFirstRun", "-fakeCamera", "-fakeObjectNames"])
        XCTAssertTrue(el(app, "home").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "whatsThis").exists)
    }

    /// Scenario: the child opens the camera, takes a picture, and taps a word. It speaks into history like
    /// a tile; nothing speaks until then. Another picture, and one Hum can't name, then Close goes back.
    @MainActor
    func testSnapTapAndClose() {
        let app = launchHum(["-skipFirstRun", "-fakeCamera", "-fakeObjectNames", "-whatsThisCamera", "-showHistory"])
        let button = el(app, "whatsThis")
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        keepScreenshot(app, "Board with the camera button")
        button.tap()

        let shutter = el(app, "whatsThis.shutter")
        XCTAssertTrue(shutter.waitForExistence(timeout: 3))
        shutter.tap()
        let dog = app.buttons["dog"]
        XCTAssertTrue(dog.waitForExistence(timeout: 5), "A picture gets words")
        XCTAssertEqual(app.buttons.matching(identifier: "whatsThis.word").count, 3)
        keepScreenshot(app, "Words for a picture")
        dog.tap()

        el(app, "whatsThis.retake").tap()
        XCTAssertTrue(shutter.waitForExistence(timeout: 3))
        shutter.tap()
        XCTAssertTrue(app.buttons["hot air balloon"].waitForExistence(timeout: 5))
        keepScreenshot(app, "Long words")

        el(app, "whatsThis.retake").tap()
        shutter.tap()
        XCTAssertTrue(app.staticTexts["Try again"].waitForExistence(timeout: 5), "No words: a calm try again")
        XCTAssertEqual(app.buttons.matching(identifier: "whatsThis.word").count, 0)
        keepScreenshot(app, "Nothing named")

        el(app, "whatsThis.close").tap()
        XCTAssertTrue(el(app, "whatsThis").waitForExistence(timeout: 3), "Close goes back to the board")
        XCTAssertFalse(shutter.exists)
        // Only the tapped word was said.
        XCTAssertTrue(app.buttons["Said: dog. Say it again."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Said: hot air balloon. Say it again."].exists)
    }

    private func keepScreenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
