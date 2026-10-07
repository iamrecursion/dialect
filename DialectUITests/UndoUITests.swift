import XCTest

/// Undo and Redo on the More screens. These check the wiring; the unit tests
/// check what each step does and when it's refused.
final class UndoUITests: FilesUITestCase {
    /// The More screen's row whose label starts with `title`, scrolled into
    /// view.
    @MainActor
    private func undoRow(_ title: String) -> XCUIElement {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
            .firstMatch
        // A list builds only the rows on screen.
        XCTAssertTrue(scrollTo(row), "no \(title)")
        return row
    }

    @MainActor
    private func openFolderMore() {
        let more = app.buttons["More"]
        XCTAssertTrue(scrollTo(more, upFirst: true), "no More")
        more.tap()
        waitForTitle("More")
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    /// A swipe's Delete undone from the folder's More, redone from an item's,
    /// and then named with its folder from another folder's More.
    @MainActor
    func testUndoesAndRedoesADelete() {
        launch(at: "folder:notes")
        waitForTitle("notes")
        swipeLeft("todo.txt", choose: "Delete")
        waitUntilGone(app.buttons["todo.txt"])

        openFolderMore()
        let undo = undoRow("Undo Delete")
        XCTAssertTrue(undo.label.contains("todo.txt"))
        XCTAssertFalse(undo.label.contains("/notes"))
        undo.tap()
        waitForTitle("notes")
        XCTAssertTrue(row("todo.txt").exists)

        longPress("notes.md")
        undoRow("Redo Delete").tap()
        waitForTitle("notes")
        waitUntilGone(app.buttons["todo.txt"])

        back()
        waitForTitle("Files")
        openFolderMore()
        XCTAssertTrue(undoRow("Undo Delete").label.contains("todo.txt in /notes"))
        XCTAssertFalse(undoRow("Redo").isEnabled)
    }

    /// Delete All took the deleted item, so Undo says why it can't, and drops
    /// the step: the next Undo reaches the step before it.
    @MainActor
    func testSaysWhyAStepCantBeUndone() {
        launch(at: "files/add", name: "projects")
        app.buttons["Folder"].tap()
        waitForTitle("New Folder")
        let create = app.buttons["Create"]
        XCTAssertTrue(scrollTo(create), "no Create")
        create.tap()
        waitForTitle("Files")
        swipeLeft("readme", choose: "Delete")
        waitUntilGone(app.buttons["readme"])

        openFolderMore()
        let trash = app.buttons["Trash"]
        XCTAssertTrue(scrollTo(trash), "no Trash")
        trash.tap()
        waitForTitle("Trash")
        app.buttons["More"].tap()
        waitForTitle("More")
        app.buttons["Delete All"].firstMatch.tap()
        XCTAssertTrue(
            text(containing: "Delete all 6 items permanently?").waitForExistence(timeout: 5))
        app.tables.buttons["Delete All"].tap()
        waitForTitle("Trash")
        back()
        waitForTitle("Files")

        openFolderMore()
        undoRow("Undo Delete").tap()
        XCTAssertTrue(
            text(containing: "This can't be undone, as readme is no longer in the Trash.")
                .waitForExistence(timeout: 5))
        app.buttons["OK"].tap()
        XCTAssertTrue(undoRow("Undo New Folder").isEnabled)
    }
}
