import XCTest

/// The app in British English and in US English: the system picks the spelling
/// from the wearer's language (here set by `-AppleLanguages`).
@MainActor
final class LocalizationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testBritishEnglishSaysColour() {
        for language in ["en-GB", "en-AU"] {
            launch(language: language, at: "settings/appearance")
            XCTAssertTrue(app.buttons["Accent Colour"].waitForExistence(timeout: 5), language)
            app.terminate()
            launch(language: language, at: "settings/appearance/accent-color")
            XCTAssertTrue(app.staticTexts["Accent Colour"].waitForExistence(timeout: 5), language)
            app.terminate()
        }
    }

    func testUSEnglishSaysColor() {
        launch(language: "en-US", at: "settings/appearance")
        XCTAssertTrue(app.buttons["Accent Color"].waitForExistence(timeout: 5))
    }

    private func launch(language: String, at path: String) {
        app.launchArguments = [
            "-AppleLanguages", "(\(language))", "-DialectPath", path, "-DialectResetSettings",
            "YES",
        ]
        app.launch()
    }
}
