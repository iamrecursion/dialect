import XCTest

/// Taps every way out of the main menu. The three top buttons share one list
/// row, where a tap could reach the wrong button or all of them, so each must
/// open exactly its own screen.
final class MainMenuUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = await XCUIApplication()
        await app.launch()
    }

    @MainActor
    func testEachTopButtonOpensItsOwnScreen() {
        for (label, title) in [
            ("New REPL", "REPL"), ("Resume Session", "Resume Session"), ("Sessions", "History"),
        ] {
            app.buttons[label].tap()
            XCTAssertTrue(
                app.staticTexts[title].waitForExistence(timeout: 5), "\(label) → \(title)")
            XCTAssertFalse(app.buttons[label].exists, "\(label) still on screen")
            goBack()
        }
    }

    @MainActor
    func testRowsOpenTheirScreens() {
        for (label, title) in [("Files", "Files"), ("Downloader", "Downloader")] {
            row(label).tap()
            XCTAssertTrue(
                app.staticTexts[title].waitForExistence(timeout: 5), "\(label) → \(title)")
            goBack()
        }
        row("Settings").tap()
        // Its first row: a list builds only the rows on screen, so Credits is not there yet.
        XCTAssertTrue(app.buttons["Editor"].waitForExistence(timeout: 5))
    }

    /// The menu's row with this label, scrolled up into view: a list builds
    /// only the rows on screen.
    @MainActor
    private func row(_ label: String) -> XCUIElement {
        let row = app.buttons[label]
        for _ in 0..<5 where !row.isHittable {
            app.swipeUp()
        }
        return row
    }

    /// Back to the menu, through the navigation bar's back button.
    @MainActor
    private func goBack() {
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Files"].waitForExistence(timeout: 5), "not back at the menu")
    }
}
