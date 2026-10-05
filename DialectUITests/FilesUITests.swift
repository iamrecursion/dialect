import XCTest

/// Browsing `-seedFiles`' sample tree: opening folders, files and sessions, and
/// the long press that opens More.
final class FilesUITests: FilesUITestCase {
    @MainActor
    func testListsTheRootWithoutHiddenItems() {
        launch()
        app.buttons["Files"].tap()
        waitForTitle("Files")
        XCTAssertTrue(app.buttons["empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(row("scripts").exists)
        XCTAssertTrue(row("readme").exists)
        XCTAssertFalse(app.buttons[".hidden-config"].exists)
    }

    @MainActor
    func testOpensNestedFolders() {
        launch(at: "files")
        open("scripts")
        waitForTitle("scripts")
        open("lib")
        waitForTitle("lib")
        XCTAssertTrue(app.buttons["a"].waitForExistence(timeout: 5))
    }

    /// Natural ordering puts `file9.txt` before `file10.txt`, where plain text
    /// order would put `file10.txt` right after `file1.txt`.
    @MainActor
    func testSortsNumbersNaturally() {
        launch(at: "folder:many")
        XCTAssertTrue(app.buttons["file1.txt"].waitForExistence(timeout: 5))
        let file9 = app.buttons["file9.txt"]
        let file10 = row("file10.txt")
        XCTAssertTrue(file9.exists && file10.exists, "file9 and file10 aren't on screen together")
        XCTAssertLessThan(file9.frame.minY, file10.frame.minY)
    }

    /// Files open as a cover with the system ✕.
    @MainActor
    func testOpensAFileInACover() {
        launch(at: "folder:notes")
        open("notes.md")
        XCTAssertTrue(text(containing: "No viewer yet").waitForExistence(timeout: 5))
        // The system's ✕, which the tree lists twice, nested.
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.exists, "no close button")
        // The folder's own, behind the cover, is still in the tree: the cover adds none.
        XCTAssertEqual(app.buttons.matching(identifier: "BackButton").count, 1)
        close.tap()
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: text(containing: "No viewer yet"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "still open")
        waitForTitle("notes")
    }

    @MainActor
    func testOpensASessionsPlaceholder() {
        launch(at: "files")
        open("demo.dial")
        waitForTitle("demo.dial")
        XCTAssertFalse(app.buttons["main.scm"].exists)
    }

    @MainActor
    func testShowsAnEmptyFolder() {
        launch(at: "folder:empty")
        XCTAssertTrue(app.staticTexts["No Items"].waitForExistence(timeout: 5))
    }

    /// A long press opens an item's More screen, and a tap still opens the
    /// item.
    @MainActor
    func testLongPressOpensMore() {
        launch(at: "folder:notes")
        let notes = row("notes.md")
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.press(forDuration: 1.2)
        waitForTitle("More")
        XCTAssertFalse(text(containing: "No viewer yet").exists, "the tap fired as well")

        // Back on the folder, a tap opens the item again.
        app.navigationBars.buttons.firstMatch.tap()
        waitForTitle("notes")
        row("notes.md").tap()
        XCTAssertTrue(text(containing: "No viewer yet").waitForExistence(timeout: 5))
    }

    @MainActor
    func testHidesExtensionsWhenAsked() {
        launch(at: "settings/file-settings")
        let toggle = app.switches["File Extensions"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Files"].waitForExistence(timeout: 5))
        app.buttons["Files"].tap()
        open("scripts")
        waitForTitle("scripts")
        XCTAssertTrue(app.buttons["prelude"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["prelude.scm"].exists)
        // Folders never had an extension to hide, and sessions hide theirs.
        app.navigationBars.buttons.firstMatch.tap()
        waitForTitle("Files")
        XCTAssertTrue(row("demo").exists)
    }

    /// Sorting is stored on the folder, so it lasts after leaving.
    @MainActor
    func testSortsAFolderAndRemembers() {
        launch(at: "folder:notes")
        folderMore("Sort")
        choose("Modified")
        waitForTitle("notes")
        folderMore("Sort")
        choose("Descending")
        waitForTitle("notes")
        // Newest first; ties by name, also descending.
        let notes = app.buttons["notes.md"]
        let feed = app.buttons["feed.xml"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        XCTAssertTrue(feed.exists)
        XCTAssertLessThan(notes.frame.minY, feed.frame.minY)

        app.navigationBars.buttons.firstMatch.tap()
        waitForTitle("Files")
        open("notes")
        waitForTitle("notes")
        XCTAssertTrue(app.buttons["notes.md"].waitForExistence(timeout: 5))
        XCTAssertLessThan(app.buttons["notes.md"].frame.minY, app.buttons["feed.xml"].frame.minY)
    }

    /// Folders first, then the kinds in order: `scripts` holds a folder and
    /// Scheme files.
    @MainActor
    func testGroupsByKind() {
        launch(at: "folder:scripts")
        folderMore("Group")
        choose("Kind")
        waitForTitle("scripts")
        let folders = app.staticTexts["Folders"]
        let scheme = app.staticTexts["Scheme"]
        XCTAssertTrue(folders.waitForExistence(timeout: 5))
        XCTAssertTrue(scheme.exists)
        XCTAssertLessThan(folders.frame.minY, scheme.frame.minY)
    }

    @MainActor
    func testShowsAndHidesHiddenItems() {
        launch(at: "files")
        folderMore("Show Hidden")
        waitForTitle("Files")
        XCTAssertTrue(row(".hidden-config").exists)

        folderMore("Hide Hidden")
        waitForTitle("Files")
        assertNoRow(".hidden-config")
    }
}
