import XCTest

/// The `dialect://launch/…` links that complications open: each lands on its
/// screen, over the menu, wherever the app was. The links arrive through the
/// debug `-DialectOpenURL` argument, which feeds the same handler as
/// `onOpenURL`: watchOS will not open a third-party scheme from outside the
/// app, so `XCUIApplication.open` cannot deliver them.
@MainActor
final class LaunchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testNewOpensANewSessionFromAnywhere() {
        launch(["-DialectPath", "settings/credits", "-DialectOpenURL", "dialect://launch/new"])
        XCTAssertTrue(app.staticTexts["REPL"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["Files"].waitForExistence(timeout: 5), "back did not reach the menu")
    }

    func testResumeOrNewStartsANewSessionWhenThereIsNone() {
        launch(["-DialectOpenURL", "dialect://launch/resume-or-new"])
        XCTAssertTrue(app.staticTexts["REPL"].waitForExistence(timeout: 5))
    }

    func testResumeOrNewResumesWhenThereIsASession() {
        launch([
            "-pretendSessionExists", "YES", "-DialectOpenURL", "dialect://launch/resume-or-new",
        ])
        XCTAssertTrue(app.staticTexts["Resume Session"].waitForExistence(timeout: 5))
    }

    /// A REPL that evaluates for real: an entry (given by the debug
    /// `-DialectREPLInput` argument, since a UI test cannot type into watchOS's
    /// text input) and its result.
    func testTheREPLEvaluatesAnEntry() {
        launch(["-DialectOpenURL", "dialect://launch/new", "-DialectREPLInput", "(+ 1 2)"])
        XCTAssertTrue(app.staticTexts["❯ (+ 1 2)"].waitForExistence(timeout: 20), "no entry")
        XCTAssertTrue(app.staticTexts["3"].waitForExistence(timeout: 20), "no result")
    }

    /// A finger tap on the REPL's input field opens the system's text input.
    /// (Tapping the field's element, as `XCUIElement.tap` does, can succeed
    /// where a finger does not: Starfire found the pinned field untappable on
    /// the watch while such a test still passed.)
    func testTappingTheREPLsFieldOpensTextInput() {
        launch(["-DialectOpenURL", "dialect://launch/new"])
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        let field = app.textFields.firstMatch.frame
        let screen = app.frame
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: field.midX / screen.width, dy: field.midY / screen.height)
        ).tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "no text input")
    }

    /// The downloads complication's link.
    func testDownloaderOpensTheDownloader() {
        launch(["-DialectOpenURL", "dialect://launch/downloader"])
        XCTAssertTrue(app.staticTexts["Downloader"].waitForExistence(timeout: 5))
    }

    /// From default settings, plus any of these launch arguments.
    private func launch(_ arguments: [String] = []) {
        app.launchArguments = ["-DialectResetSettings", "YES"] + arguments
        app.launch()
    }
}
