import XCTest

/// The companion against a fake watch: its tabs, its Files, the watch's
/// settings from its snapshot, and edits to them.
final class CompanionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// In US English, as the simulator's own language has its own words for
    /// some things.
    @MainActor
    private func launch(_ state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-fakeWatch", state, "-AppleLanguages", "(en-US)", "-AppleLocale", "en_US",
        ]
        app.launch()
        return app
    }

    @MainActor
    func testShowsAndEditsTheWatchsSettings() {
        let app = launch("connected")

        // The Watch tab says how the watch is connected.
        app.tabBars.buttons["Watch"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Apple Watch Ultra"].exists)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

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

    /// It opens on Browse. A folder's rows, Info, a file's placeholder, Show in
    /// Files from Recents, and the Trash.
    @MainActor
    func testBrowsesTheWatchsFiles() {
        let app = launch("connected")
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 5))
        let list = app.collectionViews

        // The fake watch hides extensions and shows hidden items and details.
        list.buttons["Files, Apple Watch Ultra"].tap()
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            list.buttons.matching(label("readme")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(list.buttons.matching(label(".profile")).firstMatch.exists)

        list.buttons.matching(label("notes")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["notes"].waitForExistence(timeout: 5))
        let todo = list.buttons.matching(label("todo")).firstMatch
        XCTAssertTrue(todo.waitForExistence(timeout: 5))

        app.navigationBars["notes"].buttons["More"].tap()
        app.buttons["Folder Info"].tap()
        XCTAssertTrue(app.staticTexts["Permissions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["/notes"].exists)
        app.buttons["Done"].tap()

        todo.tap()
        XCTAssertTrue(app.staticTexts["No viewer yet"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        list.buttons.matching(label("archive")).firstMatch.press(forDuration: 1)
        app.buttons["Get Info"].tap()
        XCTAssertTrue(app.staticTexts["/notes/archive"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        // An empty folder, whose title menu goes back up the path and on to Browse.
        list.buttons.matching(label("archive")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["archive"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Items"].waitForExistence(timeout: 5))
        app.navigationBars["archive"].buttons["archive"].tap()
        let files = list.buttons["Files"]
        XCTAssertTrue(files.waitForExistence(timeout: 5))
        files.tap()
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 5))
        app.navigationBars["Files"].buttons["Files"].tap()
        let browse = list.buttons["Browse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 5))
        browse.tap()

        // Recents' Show in Files stacks the folders up to the item's.
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 5))
        let recent = list.buttons.matching(label("todo")).firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        recent.press(forDuration: 1)
        app.buttons["Show in Files"].tap()
        XCTAssertTrue(app.navigationBars["notes"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(list.buttons["Trash"].waitForExistence(timeout: 5))
        list.buttons["Trash"].tap()
        XCTAssertTrue(app.navigationBars["Trash"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(label("old notes")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(label("Deleted")).firstMatch.exists)
    }

    /// With the watch away: the cache, "Folder last seen", and a folder never
    /// seen.
    @MainActor
    func testBrowsesTheCacheWhileAway() {
        let app = launch("away")
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 5))
        let list = app.collectionViews

        XCTAssertTrue(list.buttons["Files, Apple Watch Ultra"].waitForExistence(timeout: 5))
        list.buttons["Files, Apple Watch Ultra"].tap()
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            list.buttons.matching(label("readme")).firstMatch.waitForExistence(timeout: 5))
        let lastSeen = app.staticTexts.matching(label("Folder last seen")).firstMatch
        XCTAssertTrue(lastSeen.waitForExistence(timeout: 5))

        list.buttons.matching(label("scripts")).firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["Open Dialect on your watch to see this folder."]
                .waitForExistence(timeout: 5))
    }

    private func label(_ start: String) -> NSPredicate {
        return NSPredicate(format: "label BEGINSWITH %@", start)
    }
}
