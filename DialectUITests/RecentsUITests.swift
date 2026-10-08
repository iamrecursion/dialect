import XCTest

/// Recents: what's opened arrives at the top, a pin stays above it, Hide
/// removes it, and Show in Files opens its folder.
final class RecentsUITests: FilesUITestCase {
    @MainActor
    func testListsWhatWasOpenedPinsAndHides() {
        launch(at: "files/folder:notes")
        open("notes.md")
        XCTAssertTrue(text(containing: "No viewer yet").waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()
        waitForTitle("notes")
        back()
        waitForTitle("Files")
        back()
        open("Recents")
        waitForTitle("Recents")

        // Newest first, above the seeded ones.
        let opened = row("notes.md")
        XCTAssertTrue(opened.exists, "notes.md isn't listed")
        XCTAssertLessThan(opened.frame.midY, row("todo.txt").frame.midY)

        // Pinned, it moves above the newest.
        swipeRight("prelude.scm", choose: "Pin")
        let recentHeader = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Recent'")
        ).firstMatch
        XCTAssertTrue(recentHeader.waitForExistence(timeout: 5), "no Recent section")
        XCTAssertLessThan(row("prelude.scm").frame.midY, row("notes.md").frame.midY)

        swipeLeft("notes.md", choose: "Hide")
        assertNoRow("notes.md")
        XCTAssertTrue(row("todo.txt").exists)
    }

    /// The folder replaces Recents, so Back climbs to Files.
    @MainActor
    func testShowsAnItemInFiles() {
        launch(at: "recents")
        waitForTitle("Recents")
        swipeRight("todo.txt", choose: "Show in Files")
        waitForTitle("notes")
        // The last of notes' rows, scrolled to once the push has settled.
        let row = app.buttons["todo.txt"]
        let inView = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.isOnScreen(row) }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [inView], timeout: 5), .completed, "not in view")
        waitForReplace()
        back()
        waitForTitle("Files")
        back()
        XCTAssertTrue(app.buttons["Recents"].waitForExistence(timeout: 5), "not on the main menu")
    }
}
