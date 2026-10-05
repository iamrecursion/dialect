import XCTest

/// More screens, Info and Settings › Files on `-seedFiles`' sample tree. An
/// item's More opens with `more:` in the launch path.
final class FilesMoreUITests: FilesUITestCase {
    /// An item's More screen, opened directly, once its Info has loaded.
    @MainActor
    private func openMore(_ path: String) {
        launch(at: "more:\(path)")
        waitForTitle("More")
        // Info loads after the screen appears: the header's "Type · Size" line.
        XCTAssertTrue(text(containing: " · ").waitForExistence(timeout: 10), "no Info")
    }

    /// Settings › Files: Empty Trash After picks from its days, and Text
    /// Extensions opens its list.
    @MainActor
    func testSettingsHasTheBinAndTextExtensions() {
        launch(at: "settings/file-settings")
        XCTAssertTrue(app.switches["File Extensions"].waitForExistence(timeout: 5))
        let emptyTrash = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Empty Trash After'")
        ).firstMatch
        XCTAssertTrue(scrollTo(emptyTrash))
        XCTAssertTrue(app.switches["Confirm Extension Changes"].exists)
        XCTAssertTrue(emptyTrash.label.contains("30 Days"), emptyTrash.label)
        emptyTrash.tap()
        XCTAssertTrue(app.buttons["Never"].waitForExistence(timeout: 5))
        app.buttons["Never"].tap()
        XCTAssertTrue(emptyTrash.waitForExistence(timeout: 5))
        XCTAssertTrue(emptyTrash.label.contains("Never"), emptyTrash.label)

        let textExtensions = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Text Extensions'")
        ).firstMatch
        XCTAssertTrue(textExtensions.exists)
        textExtensions.tap()
        waitForTitle("Text Extensions")
        XCTAssertTrue(app.textFields["Add Extension"].exists)
    }

    @MainActor
    func testAnItemsMoreShowsItsInfo() {
        openMore("notes/notes.md")
        XCTAssertTrue(text(containing: "Text Document").waitForExistence(timeout: 5))
        let path = text(containing: "/notes/notes.md")
        scrollTo(path)
        XCTAssertTrue(path.exists)
    }

    /// Enter Session replaces More, so Back goes to the session's folder.
    @MainActor
    func testEntersASession() {
        openMore("demo.dial")
        let enter = app.buttons["Enter Session"]
        XCTAssertTrue(scrollTo(enter))
        enter.tap()
        waitForTitle("demo.dial")
        XCTAssertTrue(app.buttons["main.scm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["manifest.json"].exists)
        waitForReplace()
        app.navigationBars.buttons.firstMatch.tap()
        waitForTitle("Files")
    }

    /// Settings replaces More, so Back from it lands on the folder.
    @MainActor
    func testSettingsFromMoreReturnsToTheFolder() {
        launch(at: "folder:notes")
        folderMore("Settings")
        waitForTitle("Settings")
        waitForReplace()
        app.navigationBars.buttons.firstMatch.tap()
        waitForTitle("notes")
    }

    @MainActor
    func testShowsExtendedInfo() {
        openMore("scripts/prelude.scm")
        let extended = app.buttons["Extended"]
        scrollTo(extended)
        extended.tap()
        waitForTitle("Extended")
        XCTAssertTrue(text(containing: "rw-r--r--").waitForExistence(timeout: 5))
    }

    /// A sorted folder carries its view settings as an extended attribute.
    @MainActor
    func testFolderInfoListsTheViewAttribute() {
        launch(at: "folder:scripts")
        folderMore("Sort")
        choose("Size")
        waitForTitle("scripts")
        folderMore("Folder Info")
        waitForTitle("Folder Info")
        XCTAssertTrue(text(containing: "Folder").waitForExistence(timeout: 5))
        let items = text(containing: "Items")
        scrollTo(items)
        XCTAssertTrue(items.exists)
        let extended = app.buttons["Extended"]
        scrollTo(extended)
        extended.tap()
        waitForTitle("Extended")
        let attribute = text(containing: "com.iamrecursion.dialect.view")
        scrollTo(attribute)
        XCTAssertTrue(attribute.exists)
    }
}
