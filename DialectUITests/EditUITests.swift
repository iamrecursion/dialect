import XCTest

/// Rename and Delete on `-seedFiles`' sample tree. An item's More opens with
/// `more:` in the launch path.
final class EditUITests: FilesUITestCase {
    /// An item's Rename screen, its field filled with `name`.
    @MainActor
    private func rename(_ path: String, to name: String) {
        launch(at: "more:\(path)", name: name)
        waitForTitle("More")
        let rename = app.buttons["Rename"]
        XCTAssertTrue(scrollTo(rename), "no Rename")
        rename.tap()
        waitForTitle("Rename")
        let confirm = app.buttons["Rename"]
        XCTAssertTrue(scrollTo(confirm))
        confirm.tap()
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testRenamesAFile() {
        rename("notes/todo.txt", to: "tasks.txt")
        waitForTitle("notes")
        XCTAssertTrue(row("tasks.txt").exists)
        assertNoRow("todo.txt")
    }

    /// Changing the extension asks first, and the ✕ leaves it as it was.
    @MainActor
    func testAsksBeforeChangingAnExtension() {
        rename("notes/todo.txt", to: "todo.md")
        XCTAssertTrue(text(containing: "Change .txt to .md?").waitForExistence(timeout: 5))
        // A dialog's Cancel is its ✕, which VoiceOver calls Close.
        app.buttons["Close"].firstMatch.tap()
        waitForTitle("Rename")
        back()
        waitForTitle("notes")
        XCTAssertTrue(row("todo.txt").exists)
    }

    /// A leading dot and the extension it drops are asked about together, then
    /// the item leaves the list, as hidden items aren't shown.
    @MainActor
    func testAsksBeforeHiding() {
        rename("notes/table.csv", to: ".secret")
        XCTAssertTrue(
            text(containing: "This item will be hidden. Remove .csv?")
                .waitForExistence(timeout: 5))
        app.buttons["Remove .csv"].tap()
        waitForTitle("notes")
        XCTAssertTrue(row("todo.txt").exists)
        assertNoRow("table.csv")
    }

    /// The swipe's Delete takes the row at once; the swipe's More opens More,
    /// whose Delete returns to the folder; both items are then in the Trash.
    @MainActor
    func testDeletes() {
        launch(at: "folder:notes")
        swipeLeft("todo.txt", choose: "Delete")
        waitUntilGone(app.buttons["todo.txt"])

        swipeLeft("config.toml", choose: "More")
        waitForTitle("More")
        let delete = app.buttons["Delete"]
        XCTAssertTrue(scrollTo(delete), "no Delete")
        delete.tap()
        waitForTitle("notes")
        assertNoRow("config.toml")

        folderMore("Trash")
        waitForTitle("Trash")
        XCTAssertTrue(row("todo.txt").exists)
        XCTAssertTrue(row("config.toml").exists)
    }

    /// A folder's Delete leaves it for its parent; the root has no Delete.
    @MainActor
    func testDeletesAFolderFromItsOwnMore() {
        launch(at: "folder:empty")
        folderMore("Delete")
        waitForTitle("Files")
        assertNoRow("empty")

        let more = app.buttons["More"]
        XCTAssertTrue(scrollTo(more, upFirst: true))
        more.tap()
        waitForTitle("More")
        XCTAssertTrue(scrollTo(app.buttons["Trash"]))
        XCTAssertFalse(scrollTo(app.buttons["Delete"], reportingMisses: false))
    }
}
