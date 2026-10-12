// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// The rest of grown-up mode: Paste phrases, the AI helper, export, the Guided Access tip and Settings.
final class ParentToolsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario: the parent pastes the phrases their child says. Each line becomes one whole tile;
    /// praise and phrases already on the board are left out, with a note.
    @MainActor
    func testPastePhrases() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        el(app, "addMenu").tap()
        app.buttons["Paste phrases…"].firstMatch.tap()
        let editor = app.textViews["Phrases, one per line"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("To infinity and beyond!\nGood job\nNo thank you\nAll aboard!")
        let add = app.buttons["Add 2"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3), "Only the two new, non-praise phrases are offered")
        add.tap()
        XCTAssertTrue(el(app, "editTile.To infinity and beyond").waitForExistence(timeout: 3), "The whole phrase is one tile")
        XCTAssertTrue(el(app, "editTile.All aboard").exists)
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(el(app, "editTile.All aboard").waitForNonExistence(timeout: 3), "Adding pasted phrases is one undo step")
        XCTAssertFalse(el(app, "editTile.To infinity and beyond").exists)
    }

    /// Scenario: the AI helper starts off. It explains itself and turns on with one tap; it can't
    /// run with an empty request.
    @MainActor
    func testAIHelperStartsOffAndExplainsItself() throws {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        // On iPhone the button sits in the toolbar's More menu.
        try XCTSkipUnless(tapToolbarIfPresent(app, "aiHelper", label: "Help me set up"),
                          "No Apple Intelligence on this device, so the helper is hidden")
        XCTAssertTrue(el(app, "turnOnAI").waitForExistence(timeout: 3), "The helper is off until a parent turns it on")
        el(app, "turnOnAI").tap()
        let suggest = app.buttons["Suggest tiles"].firstMatch
        if suggest.waitForExistence(timeout: 3) {
            XCTAssertFalse(suggest.isEnabled, "Nothing to send yet")
        } else {
            // On a device where the model isn't ready, the reason shows instead.
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Apple Intelligence'")).firstMatch.exists)
        }
        let mayBeWrong = el(app, "ai.mayBeWrong")
        scrollTo(app, mayBeWrong)
        XCTAssertTrue(mayBeWrong.exists, "The helper says suggestions can be wrong and nothing is added until chosen")
    }

    /// Scenario: the first time a parent opens grown-up mode on iPhone/iPad, Hum explains Guided Access,
    /// once.
    @MainActor
    func testGuidedAccessTipShowsOnce() {
        let app = launchHum()
        el(app, "firstRun.start").tap()
        app.buttons["Next"].firstMatch.tap()
        app.buttons["Next"].firstMatch.tap()
        el(app, "firstRun.starter").tap()
        XCTAssertTrue(el(app, "editGate").waitForExistence(timeout: 5))
        el(app, "editGate").press(forDuration: 5)
        let tip = app.alerts["Tip: lock the app with Guided Access"]
        let shown = tip.waitForExistence(timeout: 5)
        shot(app, "first time in grown-up mode")
        XCTAssertTrue(shown, "The tip explains Guided Access the first time (HUM-041)")
        guard shown else { return }
        tip.buttons["Got it"].tap()
        finishEditing(app)
        el(app, "editGate").press(forDuration: 5)
        XCTAssertTrue(el(app, "exitParentMode").waitForExistence(timeout: 5))
        XCTAssertFalse(tip.waitForExistence(timeout: 2), "The tip shows only once")
    }

    /// Scenario: Export all boards opens the system's share sheet.
    @MainActor
    func testExportOpensTheShareSheet() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        tapToolbar(app, "setupSharing", label: "Setup & sharing")
        el(app, "exportAll").tap()
        // The share sheet runs in another process; its parts still show up here.
        let sheet = app.otherElements["ActivityListView"].firstMatch
        let saveToFiles = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Save to Files'")).firstMatch
        let opened = sheet.waitForExistence(timeout: 15) || saveToFiles.exists
        _ = saveToFiles.waitForExistence(timeout: 3)  // let it finish sliding up for the screenshot
        shot(app, "export share sheet")
        XCTAssertTrue(opened, "Export opens the share sheet (AirDrop, Messages, Save to Files…), not only Files")
    }

    /// Scenario: Settings has no developer screens or jargon (HUM-022).
    @MainActor
    func testSettingsHaveNoDeveloperSection() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        tapToolbar(app, "settings", label: "Settings")
        let about = el(app, "settings.about")
        scrollTo(app, about)
        XCTAssertTrue(about.exists)
        XCTAssertFalse(app.staticTexts["For developers"].exists)
        XCTAssertFalse(app.buttons["Tap-to-sound latency"].exists)
    }

    /// Scenario: Settings → About Hum shows the version, the "Important" note, the links and the credits.
    @MainActor
    func testAboutHumOpensFromSettings() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        tapToolbar(app, "settings", label: "Settings")
        let about = el(app, "settings.about")
        scrollTo(app, about)
        about.tap()
        let privacy = el(app, "about.privacy")
        XCTAssertTrue(privacy.waitForExistence(timeout: 5), "About Hum opens from Settings")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Version'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Hum is a communication tool'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Help and support"].exists)
        let credits = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'ARASAAC'")).firstMatch
        scrollTo(app, credits)
        XCTAssertTrue(credits.exists, "The symbol credits are on About Hum")
        shot(app, "about hum")
    }

    /// Scenario: switching the appearance to Dark changes the child's screen at once.
    @MainActor
    func testAppearanceDark() {
        let app = launchHum(["-skipFirstRun", "-startInParent"])
        tapToolbar(app, "settings", label: "Settings")
        let appearance = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Appearance'")).firstMatch
        scrollTo(app, appearance)
        appearance.tap()
        app.buttons["Dark"].firstMatch.tap()
        closeSheet(app)
        finishEditing(app)
        shot(app, "child after choosing dark")
        XCTAssertTrue(el(app, "tile.hi").exists)
    }
}
