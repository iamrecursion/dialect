import XCTest

/// The companion against a fake watch: its tabs, the watch's settings as the
/// snapshot gives them, and edits to them.
final class CompanionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testShowsAndEditsTheWatchsSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-fakeWatch", "connected"]
        app.launch()

        // It opens on Settings; the Watch tab says how the watch is connected.
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Watch"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Apple Watch Ultra"].exists)

        app.tabBars.buttons["Files"].tap()
        XCTAssertTrue(app.staticTexts["Coming later"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()

        // The fake watch's values, which aren't the defaults. An edit waits, as the fake watch
        // never applies it.
        let list = app.collectionViews
        list.buttons["Files"].tap()
        let hidden = list.switches.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Hidden Files")
        ).firstMatch
        XCTAssertTrue(hidden.waitForExistence(timeout: 5))
        XCTAssertEqual(hidden.value as? String, "1")
        XCTAssertFalse(list.staticTexts["Waiting for the Watch"].exists)
        hidden.switches.firstMatch.tap()
        XCTAssertEqual(hidden.value as? String, "0")
        XCTAssertTrue(list.staticTexts["Waiting for the Watch"].waitForExistence(timeout: 5))

        // Fewer steps than the 30 in the watch's history asks first; Cancel makes no edit.
        list.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Undo History"))
            .firstMatch.tap()
        app.buttons["20 Steps"].tap()
        XCTAssertTrue(app.alerts["Shorten Undo History?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(list.buttons["Undo History, 50 Steps"].waitForExistence(timeout: 5))

        list.buttons["Text Extensions, 3"].tap()
        let field = app.textFields["Add Extension"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("el\n")
        XCTAssertTrue(app.staticTexts[".el"].waitForExistence(timeout: 5))
        field.tap()
        field.typeText("png\n")
        XCTAssertTrue(
            app.staticTexts["Files already treats .png as an image."].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let count = list.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Text Extensions", "4")
        ).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        list.buttons["Credits"].tap()
        let page = list.buttons["LispKit"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.tap()
        XCTAssertTrue(app.navigationBars["LispKit"].waitForExistence(timeout: 5))
    }
}
