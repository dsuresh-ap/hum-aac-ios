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

    /// Holds the lock, the parent's way into edit mode. The gate needs 3 s; 5 s leaves room for a slow
    /// simulator. `ChildModeUITests.testThreeAndAHalfSecondHoldOpensGrownUpMode` checks the real timing.
    func openParentMode(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        el(app, "editGate").press(forDuration: 5)
        XCTAssertTrue(el(app, "exitParentMode").waitForExistence(timeout: 5), "Holding the lock should open grown-up settings", file: file, line: line)
    }

    /// Taps an editor toolbar button. On iPhone some of them sit in the toolbar's "More" (⋯) menu.
    func tapToolbar(_ app: XCUIApplication, _ id: String, label: String) {
        XCTAssertTrue(tapToolbarIfPresent(app, id, label: label), "\(label) should be in the toolbar's More menu")
    }

    /// Like `tapToolbar`, but returns false instead of failing when the button isn't there at all
    /// (for buttons only some devices have, like the AI helper).
    @discardableResult
    func tapToolbarIfPresent(_ app: XCUIApplication, _ id: String, label: String) -> Bool {
        let direct = el(app, id)
        // Give a sheet that is closing a moment to get out of the way.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: direct)
        if XCTWaiter.wait(for: [ready], timeout: 3) == .completed {
            direct.tap()
            return true
        }
        let more = moreButton(app)
        guard more.exists else { return false }
        let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier != %@", label, id)).firstMatch
        // The first tap on "More" right after entering the editor is sometimes ignored (BUGS.md, HUM-014).
        for _ in 0..<2 where !item.exists {
            more.tap()
            _ = item.waitForExistence(timeout: 2)
        }
        guard item.exists else { return false }
        item.tap()
        return true
    }

    /// The toolbar's "More" (⋯) button. iOS 26 and later name it `OverflowBarButtonItem`; iOS 18 only labels it.
    func moreButton(_ app: XCUIApplication) -> XCUIElement {
        let named = app.buttons["OverflowBarButtonItem"].firstMatch
        if named.exists { return named }
        // Only in the navigation bar: the child's phone pages have a "More" tile too.
        return app.navigationBars.buttons.matching(NSPredicate(format: "label == 'More' AND identifier == ''")).firstMatch
    }

    /// Taps the editor's Undo, which on iPhone can be in the toolbar's More menu.
    func tapUndo(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(tapToolbarIfPresent(app, "Undo", label: "Undo"), "Undo should be in the toolbar", file: file, line: line)
    }

    /// The element whose accessibility label is exactly `label` (menu items, dialog buttons, rows).
    func labeled(_ app: XCUIApplication, _ label: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
    }

    /// A dialog's button, not the form button with the same title underneath it.
    func dialogButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        // An action sheet or alert holds its own buttons (on iOS 18 they come before the form's in the tree).
        for container in [app.sheets, app.alerts] {
            let button = container.buttons[label].firstMatch
            if button.waitForExistence(timeout: 1) { return button }
        }
        // Otherwise (an iPad popover, the Mac): the last match, because the dialog is on top.
        let buttons = app.buttons.matching(NSPredicate(format: "label == %@", label))
        _ = buttons.firstMatch.waitForExistence(timeout: 3)
        return buttons.element(boundBy: max(buttons.count - 1, 0))
    }

    /// Swipes up (at most 15 times, never forever) until `element` is on screen.
    func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<15 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }

    /// Sets a SwiftUI Toggle. Scrolls the form until the switch is on screen.
    func setSwitch(_ app: XCUIApplication, _ label: String, on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = app.switches[label].firstMatch
        scrollTo(app, toggle)
        // Just inside the bottom edge it can sit under the sheet's bottom bar (a smaller iPad): one more swipe.
        if toggle.exists && toggle.frame.maxY > app.frame.maxY * 0.75 { app.swipeUp() }
        XCTAssertTrue(toggle.exists, "No switch “\(label)”", file: file, line: line)
        if (toggle.value as? String == "1") != on {
            // The switch itself sits at the trailing edge of the row, about 30 pt in (rows are wider on iPad).
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -32, dy: 0)).tap()
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
        // iOS 26 and later name it `BackButton`; iOS 18 leaves it unnamed. Not the editor's own "Home & folders".
        app.navigationBars.buttons.matching(NSPredicate(format: "label == %@ AND (identifier == 'BackButton' OR identifier == '')", parent)).firstMatch.tap()
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
