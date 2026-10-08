import XCTest

/// Select mode on `-seedFiles`' sample tree: entering it, toggling rows, and
/// its buttons.
final class SelectUITests: FilesUITestCase {
    /// One of the folder's buttons, scrolled back up to.
    @MainActor
    private func button(_ label: String) -> XCUIElement {
        let button = app.buttons[label]
        XCTAssertTrue(scrollTo(button, upFirst: true), "no \(label)")
        return button
    }

    /// The Select swipe selects its row; a tap selects another, and opens
    /// nothing; Done leaves select mode.
    @MainActor
    func testSwipeSelectTapAndDone() {
        launch(at: "files/folder:notes")
        waitForTitle("notes")
        swipeRight("todo.txt", choose: "Select")
        waitForTitle("1 Selected")
        XCTAssertTrue(row("todo.txt").isSelected)

        open("notes.md")
        waitForTitle("2 Selected")
        XCTAssertTrue(row("notes.md").isSelected)
        open("todo.txt")
        waitForTitle("1 Selected")
        XCTAssertFalse(row("todo.txt").isSelected)

        button("Done").tap()
        waitForTitle("notes")
        XCTAssertFalse(row("notes.md").isSelected)
        XCTAssertTrue(button("Add").exists)

        // Outside select mode, the folder's More shares the folder itself.
        button("More").tap()
        waitForTitle("More")
        let share = app.buttons["Share"]
        XCTAssertTrue(scrollTo(share), "no Share")
        share.tap()
        XCTAssertTrue(text(containing: "notes.zip").waitForExistence(timeout: 5), "no sheet")
    }

    /// Clipboard › Select, two rows, then Copy; then two rows deleted from
    /// More, which More's Undo brings back.
    @MainActor
    func testCopyAndDeleteSelected() {
        launch(at: "files/folder:notes")
        waitForTitle("notes")
        button("Clipboard").tap()
        waitForTitle("Clipboard")
        app.buttons["Select"].tap()
        waitForTitle("Select Items")
        XCTAssertFalse(button("Copy").isEnabled)
        open("todo.txt")
        open("notes.md")
        waitForTitle("2 Selected")
        button("Copy").tap()
        waitForTitle("notes")
        XCTAssertEqual(button("Clipboard").value as? String, "2 items")

        swipeRight("data.json", choose: "Select")
        open("feed.xml")
        waitForTitle("2 Selected")
        button("More").tap()
        waitForTitle("More")
        // Share opens the system's sheet with the zip; closing it sends nothing.
        let share = app.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "no Share")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: share)
        waitForExpectations(timeout: 5)
        share.tap()
        XCTAssertTrue(text(containing: "Archive.zip").waitForExistence(timeout: 5), "no sheet")
        app.buttons["Close"].firstMatch.tap()
        waitForTitle("More")
        // The folder's own Delete is hidden.
        XCTAssertFalse(app.buttons["Delete"].exists)
        app.buttons["Delete Selected"].tap()
        waitForTitle("notes")
        assertNoRow("data.json")
        assertNoRow("feed.xml")

        button("More").tap()
        waitForTitle("More")
        XCTAssertFalse(app.buttons["Select All"].exists, "still in select mode")
        let undoDelete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Undo Delete'"))
            .firstMatch
        XCTAssertTrue(scrollTo(undoDelete), "no Undo Delete")
        XCTAssertTrue(undoDelete.label.contains("2 items"))
        undoDelete.tap()
        waitForTitle("notes")
        XCTAssertTrue(row("data.json").exists)
        XCTAssertTrue(row("feed.xml").exists)
    }
}
