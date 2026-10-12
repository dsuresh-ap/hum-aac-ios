// Copyright 2026 The Hum Authors
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// Small helpers shared by the UI tests. Every launch uses -uiTesting: an in-memory store and fresh settings.
@MainActor
extension XCTestCase {
    func launchHum(_ args: [String] = [], file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + args
        app.launch()
        return app
    }

    func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Holds the lock, the parent's way into edit mode. The gate needs 3 s, but on iPad touches near the
    /// top edge start late, so 3.5 s isn't enough there (BUGS.md, HUM-044). Hold for 5 s.
    func openParentMode(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        el(app, "editGate").press(forDuration: 5)
        XCTAssertTrue(el(app, "exitParentMode").waitForExistence(timeout: 5), "Holding the lock should open grown-up settings", file: file, line: line)
    }

    /// Taps an editor toolbar button. On iPhone some of them sit in the toolbar's "More" (⋯) menu.
    func tapToolbar(_ app: XCUIApplication, _ id: String, label: String) {
        let direct = el(app, id)
        // Give a sheet that is closing a moment to get out of the way.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: direct)
        if XCTWaiter.wait(for: [ready], timeout: 3) == .completed { return direct.tap() }
        let more = app.buttons["OverflowBarButtonItem"].firstMatch
        let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier != %@", label, id)).firstMatch
        // The first tap on "More" right after entering the editor is sometimes ignored (BUGS.md, HUM-014).
        for _ in 0..<2 where !item.exists {
            more.tap()
            _ = item.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(item.exists, "\(label) should be in the toolbar's More menu")
        item.tap()
    }

    /// The element whose accessibility label is exactly `label` (menu items, dialog buttons, rows).
    func labeled(_ app: XCUIApplication, _ label: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
    }

    /// A dialog's button: the last match, because a form button with the same title sits underneath.
    func dialogButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", label))
        _ = buttons.firstMatch.waitForExistence(timeout: 3)
        return buttons.element(boundBy: max(buttons.count - 1, 0))
    }

    /// Swipes up (at most 8 times, never forever) until `element` is on screen.
    func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<15 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }

    /// Sets a SwiftUI Toggle. Scrolls the form until the switch is on screen.
    func setSwitch(_ app: XCUIApplication, _ label: String, on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = app.switches[label].firstMatch
        scrollTo(app, toggle)
        XCTAssertTrue(toggle.exists, "No switch “\(label)”", file: file, line: line)
        if (toggle.value as? String == "1") != on {
            // The switch itself sits at the trailing edge of the row.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0", "“\(label)” didn't change", file: file, line: line)
    }

    /// Saves the open tile editor with `phrase` typed into "What does this tile say?".
    func typePhraseAndSave(_ app: XCUIApplication, _ phrase: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = el(app, "spokenTextField")
        XCTAssertTrue(field.waitForExistence(timeout: 3), "The tile editor should open", file: file, line: line)
        field.tap()
        field.typeText(phrase)
        el(app, "saveTile").tap()
    }

    /// Closes the sheet on top with its Done button (not the editor's own Done, which has the same title).
    func closeSheet(_ app: XCUIApplication) {
        app.buttons.matching(NSPredicate(format: "label == 'Done' AND identifier != 'exitParentMode'")).firstMatch.tap()
    }

    /// A board's row in Home & folders (its label is "<name>, <rows> × <columns>").
    func boardRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ", ")).firstMatch
    }

    /// The back button of a pushed screen inside a sheet (not the editor's own toolbar behind it).
    func goBack(_ app: XCUIApplication, from parent: String) {
        app.buttons.matching(NSPredicate(format: "identifier == 'BackButton' AND label == %@", parent)).firstMatch.tap()
    }

    /// Leaves the editor for the child's board.
    func finishEditing(_ app: XCUIApplication) {
        el(app, "exitParentMode").tap()
        _ = el(app, "editGate").waitForExistence(timeout: 3)
    }

    /// Long-presses an element and picks a context menu item.
    func contextMenu(_ app: XCUIApplication, _ id: String, _ item: String) {
        el(app, id).press(forDuration: 1.2)
        app.buttons[item].firstMatch.tap()
    }

    /// A screenshot kept in the test results, for reviewing layout by eye.
    func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        true  // The Mac has room like an iPad: no phone layout.
        #endif
    }

    /// A real family's setup to import, kept out of git (see TestFixtures/README.md).
    /// The simulator can read the Mac's files, so the path next to this source file works.
    static func localFixture(_ name: String) -> String? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/Local/\(name)")
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }
}
