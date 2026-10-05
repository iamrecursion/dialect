import XCTest

/// `make smoke-test`: the quick check that the app starts and its main screens
/// open, run on its own before the full UI suite. `make ui-test` skips it.
final class SmokeUITests: FilesUITestCase {
    /// The main menu, Files, a folder, its More and the Trash.
    @MainActor
    func testOpensFilesAndTheTrash() {
        launch()
        let files = app.buttons["Files"]
        XCTAssertTrue(files.waitForExistence(timeout: 5))
        files.tap()
        waitForTitle("Files")
        open("notes")
        waitForTitle("notes")
        // The folder's first row, so no scrolling away from More.
        XCTAssertTrue(row("config.toml").exists)
        folderMore("Trash")
        waitForTitle("Trash")
        XCTAssertTrue(row("readme").exists)
    }

    /// Settings and a new REPL open from the main menu.
    @MainActor
    func testOpensSettingsAndTheREPL() {
        launch(at: "settings/file-settings")
        waitForTitle("Files")
        XCTAssertTrue(app.switches["File Extensions"].waitForExistence(timeout: 5))
        app.terminate()
        launch(at: "new-repl")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
    }
}
