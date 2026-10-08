import XCTest

/// Path: a jump back up the folders, asking first when it would drop a
/// selection, and one to the main menu.
final class PathUITests: FilesUITestCase {
    @MainActor
    func testJumpsUpAskingAboutASelection() {
        launch(at: "files/folder:scripts/lib/a/b")
        swipeRight("c", choose: "Select")
        waitForTitle("1 Selected")
        folderMore("Path")
        waitForTitle("Path")

        open("lib")
        let question = text(containing: "Deselect 1 item and go to lib?")
        XCTAssertTrue(question.waitForExistence(timeout: 5), "didn't ask")
        // A dialog's Cancel is its ✕, which VoiceOver calls Close.
        app.buttons["Close"].firstMatch.tap()
        waitForTitle("Path")

        open("lib")
        XCTAssertTrue(app.buttons["Go"].waitForExistence(timeout: 5))
        app.buttons["Go"].tap()
        waitForTitle("lib")
        // Select mode has ended.
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 5))

        folderMore("Path")
        waitForTitle("Path")
        open("Menu")
        XCTAssertTrue(app.buttons["Recents"].waitForExistence(timeout: 5), "not on the main menu")
    }
}
