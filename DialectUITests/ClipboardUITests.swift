import XCTest

/// Copy, Paste and Move on `-seedFiles`' sample tree: the swipe, More's items,
/// the Clipboard button and screen, and a clash.
final class ClipboardUITests: FilesUITestCase {
    /// The folder's Clipboard button, scrolled back up to.
    @MainActor
    private func clipboardButton() -> XCUIElement {
        let button = app.buttons["Clipboard"]
        XCTAssertTrue(scrollTo(button, upFirst: true), "no Clipboard")
        return button
    }

    /// Waits for the Clipboard button to say how many items it holds; "" for
    /// none.
    @MainActor
    private func waitForCount(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = clipboardButton()
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: button)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
            "the Clipboard button's value is \(String(describing: button.value))", file: file,
            line: line)
    }

    @MainActor
    private func openClipboard() {
        clipboardButton().tap()
        waitForTitle("Clipboard")
    }

    @MainActor
    private func tapAction(_ label: String) {
        let action = app.buttons[label]
        XCTAssertTrue(scrollTo(action), "no \(label)")
        action.tap()
    }

    /// The Copy swipe, then Paste from the Clipboard screen, twice: the second
    /// meets the first's copy and keeps both.
    @MainActor
    func testCopySwipeAndPaste() {
        launch(at: "files/folder:notes")
        waitForTitle("notes")
        swipeRight("todo.txt", choose: "Copy")
        waitForCount("1 item")
        back()
        waitForTitle("Files")
        waitForCount("1 item")

        openClipboard()
        tapAction("Paste")
        waitForTitle("Files")
        XCTAssertTrue(row("todo.txt").waitForExistence(timeout: 5))
        // Paste keeps the clipboard.
        waitForCount("1 item")

        openClipboard()
        tapAction("Paste")
        let keepBoth = app.buttons["Keep Both"]
        XCTAssertTrue(keepBoth.waitForExistence(timeout: 5), "no clash")
        XCTAssertTrue(text(containing: "already exists in Files").exists)
        XCTAssertTrue(scrollTo(keepBoth))
        keepBoth.tap()
        waitForTitle("Files")
        XCTAssertTrue(row("todo 2.txt").waitForExistence(timeout: 5))
    }

    /// More's Copy, then a folder's More › Move puts the item inside it, and
    /// the clipboard empties.
    @MainActor
    func testMoreCopyAndMove() {
        launch(at: "more:readme")
        waitForTitle("More")
        XCTAssertTrue(text(containing: " · ").waitForExistence(timeout: 10), "no Info")
        // Nothing to paste yet.
        XCTAssertFalse(app.buttons["Paste"].exists)
        tapAction("Copy")
        waitForTitle("Files")
        waitForCount("1 item")

        longPress("notes")
        tapAction("Move")
        waitForTitle("Files")
        assertNoRow("readme")
        waitForCount("")
        open("notes")
        waitForTitle("notes")
        XCTAssertTrue(row("readme").waitForExistence(timeout: 5))
    }

    /// The screen: empty at first, then what was copied under where it is, a
    /// second Copy replacing the first, and Clear Clipboard.
    @MainActor
    func testTheClipboardScreen() {
        launch(at: "files/clipboard")
        waitForTitle("Clipboard")
        XCTAssertTrue(app.staticTexts["The clipboard is empty"].waitForExistence(timeout: 5))
        let paste = app.buttons["Paste"]
        XCTAssertTrue(scrollTo(paste))
        XCTAssertFalse(paste.isEnabled)
        back()
        waitForTitle("Files")

        open("notes")
        waitForTitle("notes")
        swipeRight("todo.txt", choose: "Copy")
        openClipboard()
        XCTAssertTrue(app.staticTexts["In /notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["todo.txt"].exists)
        back()
        back()
        waitForTitle("Files")

        longPress("scripts")
        tapAction("Copy")
        waitForTitle("Files")
        openClipboard()
        XCTAssertTrue(app.staticTexts["In Files"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["scripts"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["todo.txt"].exists)

        tapAction("Clear Clipboard")
        waitForTitle("Files")
        waitForCount("")
    }
}
