import XCTest

/// The Trash on `-seedFiles`' sample bin: `readme` (an hour ago, its place
/// taken), `old-notes.md`, `draft.scm` and `draft 2.scm`, `sketch.scm` (its
/// folder gone) and `expired.txt` (40 days ago). These check the screens; the
/// unit tests check where items go back to and what's dated.
final class BinUITests: FilesUITestCase {
    @MainActor
    private func openTrash(arguments: [String] = []) {
        launch(at: "files/trash", arguments: arguments)
        waitForTitle("Trash")
    }

    /// The seeded `readme`'s dated name: the local date an hour before now,
    /// when it was deleted.
    private var datedReadme: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "readme-\(formatter.string(from: Date().addingTimeInterval(-3600)))"
    }

    @MainActor
    private func backToFiles() {
        back()
        waitForTitle("Files")
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }

    /// The list, newest first with the days left and without the expired item;
    /// a restore whose place is taken, and its alert; a plain restore; an
    /// item's information; and both restored items back in Files.
    @MainActor
    func testListsAndRestores() {
        openTrash()
        let readme = row("readme")
        XCTAssertTrue(readme.exists)
        XCTAssertTrue("\(readme.value ?? "")".contains("days left"))
        XCTAssertLessThan(readme.frame.minY, row("old-notes.md").frame.minY)
        assertNoRow("expired.txt")

        swipeRight("readme", choose: "Restore")
        XCTAssertTrue(
            text(containing: "It came back as \(datedReadme)").waitForExistence(timeout: 5))
        app.buttons["OK"].tap()
        swipeRight("old-notes.md", choose: "Restore")
        waitUntilGone(app.buttons["old-notes.md"])

        open("draft 2.scm")
        waitForTitle("Info")
        XCTAssertTrue(text(containing: "Original Location").waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "/scripts").exists)
        back()
        waitForTitle("Trash")

        backToFiles()
        XCTAssertTrue(row("readme").exists)
        XCTAssertTrue(row(datedReadme).exists)
        open("notes")
        waitForTitle("notes")
        XCTAssertTrue(row("old-notes.md").exists)
    }

    /// Delete Permanently asks first: the ✕ keeps the item, Delete Permanently
    /// takes it.
    @MainActor
    func testDeletesPermanentlyOnceConfirmed() {
        openTrash()
        swipeLeft("draft.scm", choose: "Delete Permanently")
        XCTAssertTrue(
            text(containing: "Delete “draft.scm” permanently?").waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(row("draft.scm").exists)

        swipeLeft("draft.scm", choose: "Delete Permanently")
        // The dialog's button is in a table; the swipe's, behind it, has the same label.
        let confirm = app.tables.buttons["Delete Permanently"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        waitUntilGone(app.buttons["draft.scm"])
        XCTAssertTrue(row("draft 2.scm").exists)
    }

    /// Restore All empties the bin and says how many came back dated.
    @MainActor
    func testRestoresAll() {
        openTrash()
        app.buttons["More"].tap()
        waitForTitle("More")
        app.buttons["Restore All"].tap()
        XCTAssertTrue(
            text(containing: "1 item came back with its deletion date added")
                .waitForExistence(timeout: 5))
        app.buttons["OK"].tap()
        waitForTitle("Trash")
        XCTAssertTrue(text(containing: "The Trash is empty").waitForExistence(timeout: 5))
    }

    /// Select mode: a tap selects instead of opening Info; More restores the
    /// selection, then deletes another for good once confirmed.
    @MainActor
    func testRestoresAndDeletesTheSelection() {
        openTrash()
        app.buttons["Select"].tap()
        waitForTitle("Select Items")
        open("old-notes.md")
        open("draft.scm")
        waitForTitle("2 Selected")
        XCTAssertTrue(row("draft.scm").isSelected)
        app.buttons["More"].tap()
        waitForTitle("More")
        app.buttons["Restore Selected"].tap()
        waitForTitle("Trash")
        waitUntilGone(app.buttons["old-notes.md"])
        assertNoRow("draft.scm")
        XCTAssertTrue(row("draft 2.scm").exists)

        app.buttons["Select"].tap()
        open("sketch.scm")
        waitForTitle("1 Selected")
        app.buttons["More"].tap()
        waitForTitle("More")
        app.buttons["Delete Selected"].tap()
        XCTAssertTrue(
            text(containing: "Delete 1 item permanently?").waitForExistence(timeout: 5))
        app.tables.buttons["Delete Selected"].tap()
        waitForTitle("Trash")
        waitUntilGone(app.buttons["sketch.scm"])
        XCTAssertTrue(app.buttons["Select"].exists)
    }

    /// Delete All empties the bin, and the folder's More then grays out Trash.
    @MainActor
    func testDeletesAll() {
        openTrash()
        app.buttons["More"].tap()
        waitForTitle("More")
        app.buttons["Delete All"].firstMatch.tap()
        XCTAssertTrue(
            text(containing: "Delete all 5 items permanently?").waitForExistence(timeout: 5))
        app.tables.buttons["Delete All"].tap()
        waitForTitle("Trash")
        XCTAssertTrue(text(containing: "The Trash is empty").waitForExistence(timeout: 5))
        backToFiles()
        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        waitForTitle("More")
        let trash = app.buttons["Trash"]
        XCTAssertTrue(scrollTo(trash))
        XCTAssertFalse(trash.isEnabled)
    }

    /// With Empty Trash After at 1 day, opening the bin removes everything
    /// older.
    @MainActor
    func testEmptiesItselfOfWhatsExpired() {
        openTrash(arguments: ["-files.emptyTrashAfter", "1"])
        let readme = row("readme")
        XCTAssertTrue(readme.exists)
        XCTAssertTrue("\(readme.value ?? "")".contains("1 day left"))
        // Only `readme` is left, so there's nothing to scroll to.
        XCTAssertFalse(app.buttons["old-notes.md"].exists)
        XCTAssertFalse(app.buttons["draft.scm"].exists)
    }

    /// British English calls it the Bin.
    @MainActor
    func testBritishEnglishSaysBin() {
        launch(at: "files/trash", language: "en-GB")
        waitForTitle("Bin")
    }
}
