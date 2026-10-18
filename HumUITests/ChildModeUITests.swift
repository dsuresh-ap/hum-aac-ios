// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// The child's screen: tapping tiles, folders, Home and Back, and the optional strip and history box.
final class ChildModeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Where every starter tile is, so a test can check that nothing moved.
    @MainActor
    private func frames(_ app: XCUIApplication, _ labels: [String]) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: labels.map { ($0, el(app, "tile.\($0)").frame) })
    }

    private let starter = ["hi", "bye-bye", "look!", "uh oh", "funny", "again!", "let's go", "up", "more", "snack",
                           "play", "outside", "help", "break", "too loud", "no thank you", "stop", "all done"]

    /// Scenario: protest and refusal tiles are exactly as big as request tiles.
    @MainActor
    func testProtestTilesAreAsBigAsRequestTiles() {
        let app = launchHum(["-skipFirstRun"])
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 5))
        let request = el(app, "tile.let's go").frame.size
        for label in ["no thank you", "stop", "all done"] {
            let size = el(app, "tile.\(label)").frame.size
            XCTAssertEqual(size.width, request.width, accuracy: 0.5, "“\(label)” must be as wide as “let's go”")
            XCTAssertEqual(size.height, request.height, accuracy: 0.5, "“\(label)” must be as tall as “let's go”")
        }
    }

    /// Scenario: on iPhone every tile is at least 88 × 88 points (the spec's minimum hit target).
    @MainActor
    func testTilesMeetTheMinimumHitTarget() {
        let app = launchHum(["-skipFirstRun"])
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 5))
        let size = el(app, "tile.hi").frame.size
        XCTAssertGreaterThanOrEqual(size.width, 88)
        XCTAssertGreaterThanOrEqual(size.height, 88)
    }

    /// Scenario: a board taller than the screen scrolls down. A swipe that starts on a tile scrolls
    /// without speaking; a tap on a tile that was below the fold speaks.
    @MainActor
    func testTallBoardScrollsAndScrollingNeverSpeaks() {
        let app = launchHum(["-skipFirstRun", "-tallHome", "-demoHistory"])
        XCTAssertTrue(el(app, "boardScroll").waitForExistence(timeout: 5), "A 12-row Home scrolls")
        let bottom = el(app, "tile.bottom")
        XCTAssertFalse(bottom.isHittable, "The last row starts below the fold")
        let help = el(app, "tile.help")
        for _ in 0..<4 where !bottom.isHittable {
            (help.isHittable ? help : el(app, "boardScroll")).swipeUp()
        }
        XCTAssertTrue(bottom.isHittable, "Scrolling down reaches the last row")
        XCTAssertFalse(app.buttons["Said: Help me. Say it again."].exists, "Starting a scroll on a tile must not speak it")
        bottom.tap()
        XCTAssertTrue(app.buttons["Said: All the way down! Say it again."].waitForExistence(timeout: 3), "A tap still speaks")
    }

    /// Scenario: the child taps the same tile again and again (stimming). Every tap counts, and the
    /// parent sees one history entry with the count, not a wall of duplicates and never a warning.
    @MainActor
    func testRepeatedTapsAreAllHeardAndCounted() {
        let app = launchHum(["-skipFirstRun"])
        let tile = el(app, "tile.uh oh")
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        for _ in 0..<10 { tile.tap() }
        XCTAssertFalse(app.alerts.firstMatch.exists, "Fast tapping must never show a warning")
        openParentMode(app)
        tapToolbar(app, "history", label: "History")
        XCTAssertTrue(app.staticTexts["10 times in a row"].waitForExistence(timeout: 3), "All 10 taps should be counted")
    }

    /// Scenario: a folder tile speaks its phrase and opens its board; Back and Home return.
    @MainActor
    func testFolderSpeaksOpensAndHomeReturns() {
        let app = launchHum(["-skipFirstRun", "-demoFolder", "-demoHistory"])
        el(app, "tile.snack").tap()
        XCTAssertTrue(el(app, "tile.crackers").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Food"].exists, "The folder's name shows at the top")
        XCTAssertTrue(app.buttons["Said: Let's have a snack. Say it again."].exists, "Opening the folder also speaks its phrase")
        el(app, "home").tap()
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 3))
        XCTAssertFalse(el(app, "back").isHittable, "Back is hidden on Home")
    }

    /// Scenario: Home and the lock never move between boards (motor planning).
    @MainActor
    func testHomeAndLockStayPutInFolders() {
        let app = launchHum(["-skipFirstRun", "-demoFolder"])
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 5))
        let home = el(app, "home").frame, lock = el(app, "editGate").frame
        el(app, "tile.snack").tap()
        XCTAssertTrue(el(app, "tile.crackers").waitForExistence(timeout: 3))
        XCTAssertEqual(el(app, "home").frame, home)
        XCTAssertEqual(el(app, "editGate").frame, lock)
    }

    /// Scenario: "Go back to Home after a tile in a folder speaks".
    @MainActor
    func testReturnHomeAfterFolderTap() {
        let app = launchHum(["-skipFirstRun", "-demoFolder"])
        openParentMode(app)
        tapToolbar(app, "settings", label: "Settings")
        setSwitch(app, "Go back to Home after a tile in a folder speaks", on: true)
        closeSheet(app)
        finishEditing(app)
        el(app, "tile.snack").tap()
        el(app, "tile.juice").tap()
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 3), "After “juice” speaks, Home should show")
    }

    /// Scenario: hiding a tile leaves its spot empty and no other tile moves.
    @MainActor
    func testHiddenTileLeavesAHoleAndNothingMoves() {
        let app = launchHum(["-skipFirstRun"])
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 5))
        let before = frames(app, starter.filter { $0 != "funny" })
        openParentMode(app)
        contextMenu(app, "editTile.funny", "Hide tile")
        XCTAssertTrue(el(app, "editTile.funny").label.hasSuffix("Hidden"), "The editor still shows a hidden tile, marked hidden")
        finishEditing(app)
        XCTAssertFalse(el(app, "tile.funny").exists, "The child doesn't see a hidden tile")
        XCTAssertEqual(frames(app, starter.filter { $0 != "funny" }), before, "No other tile moved")
    }

    /// Scenario: with the sentence strip on, tapped tiles collect in the strip. Each one still speaks,
    /// the strip can say them all, and Clear empties it.
    @MainActor
    func testSentenceStrip() {
        let app = launchHum(["-skipFirstRun"])
        openParentMode(app)
        tapToolbar(app, "settings", label: "Settings")
        setSwitch(app, "Sentence strip", on: true)
        closeSheet(app)
        finishEditing(app)
        el(app, "tile.let's go").tap()
        el(app, "tile.outside").tap()
        let strip = app.buttons["Say them all: Let's go! I want to go outside"]
        XCTAssertTrue(strip.waitForExistence(timeout: 3))
        strip.tap()
        app.buttons["Clear the sentence"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Say them all: "].waitForExistence(timeout: 3), "Clear empties the strip")
    }

    /// Scenario: with labels off, tiles show only the picture, and VoiceOver still reads the phrase.
    @MainActor
    func testLabelsOff() {
        let app = launchHum(["-skipFirstRun"])
        openParentMode(app)
        tapToolbar(app, "settings", label: "Settings")
        setSwitch(app, "Show labels", on: false)
        closeSheet(app)
        finishEditing(app)
        let tile = el(app, "tile.snack")
        XCTAssertTrue(tile.waitForExistence(timeout: 3))
        XCTAssertEqual(tile.label, "Let's have a snack", "VoiceOver reads the whole phrase")
        XCTAssertFalse(app.staticTexts["snack"].exists, "No label text on the tile")
    }

    /// Scenario: VoiceOver reads each tile's whole phrase, and a folder tile says it opens a board.
    @MainActor
    func testVoiceOverLabels() {
        let app = launchHum(["-skipFirstRun", "-demoFolder"])
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "tile.hi").label, "Hi!")
        XCTAssertEqual(el(app, "tile.no thank you").label, "No thank you")
        XCTAssertEqual(el(app, "editGate").label, "Grown-up settings")
    }

    /// Scenario: the two-finger triple-tap gate replaces the lock; the corner keeps its size.
    @MainActor
    func testTwoFingerGateHidesTheLock() {
        let app = launchHum(["-skipFirstRun"])
        openParentMode(app)
        tapToolbar(app, "settings", label: "Settings")
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'To open grown-up settings'")).firstMatch
        scrollTo(app, picker)
        picker.tap()
        app.buttons["Two-finger triple-tap"].firstMatch.tap()
        closeSheet(app)
        finishEditing(app)
        XCTAssertTrue(el(app, "tile.hi").waitForExistence(timeout: 3))
        XCTAssertFalse(el(app, "editGate").exists, "No lock with the two-finger gate")
    }

    /// Scenario: a parent holds the lock for a little over the 3 seconds it asks for. On iPad the top
    /// edge used to hold touches back, so 3.5 s wasn't enough (HUM-044).
    @MainActor
    func testThreeAndAHalfSecondHoldOpensGrownUpMode() {
        let app = launchHum(["-skipFirstRun"])
        XCTAssertTrue(el(app, "editGate").waitForExistence(timeout: 5))
        el(app, "editGate").press(forDuration: 3.5)
        XCTAssertTrue(el(app, "exitParentMode").waitForExistence(timeout: 3), "A 3.5 s hold opens grown-up mode")
    }

    /// Scenario: the child's history box reads like a sentence (oldest first, newest at the trailing
    /// end, kept in view) and replays on tap.
    @MainActor
    func testHistoryBox() {
        let app = launchHum(["-skipFirstRun", "-demoHistory"])
        let newest = app.buttons["Said: Let's have crackers! Say it again."]
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        let older = app.buttons["Said: Look at that! Say it again."]
        XCTAssertLessThan(older.frame.maxX, newest.frame.minX, "Older entries sit before newer ones")
        XCTAssertTrue(newest.isHittable, "The newest entry is in view")
        // HUM-021: no doubled punctuation ("Hi!."). The demo history may already show a "Hi!"; the new one is last.
        let saidHi = app.buttons.matching(NSPredicate(format: "label == %@", "Said: Hi! Say it again."))
        let before = saidHi.count
        el(app, "tile.hi").tap()
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > %d", before), object: saidHi)
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 3), .completed)
        let newHi = saidHi.element(boundBy: saidHi.count - 1)
        XCTAssertGreaterThan(newHi.frame.minX, newest.frame.maxX, "A new entry is added at the end")
        let inView = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: newHi)
        XCTAssertEqual(XCTWaiter.wait(for: [inView], timeout: 3), .completed, "The bar scrolls to show the new entry")
    }
}
