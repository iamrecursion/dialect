import XCTest

/// Add and the name screen on `-seedFiles`' sample tree. `-DialectNameInput`
/// fills the name, as a UI test can't type into watchOS's text input. These
/// check the screens' wiring; the unit tests check the naming rules.
final class AddUITests: FilesUITestCase {
    /// Add's item, then its name screen.
    @MainActor
    private func add(_ item: String, title: String) {
        let button = app.buttons[item]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no \(item) in Add")
        button.tap()
        waitForTitle(title)
    }

    @MainActor
    private func tap(_ label: String) {
        let button = app.buttons[label]
        XCTAssertTrue(scrollTo(button), "no \(label)")
        button.tap()
    }

    /// The new file's Extension row, which shows the choice.
    @MainActor
    private var extensionRow: XCUIElement {
        return app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Extension'"))
            .firstMatch
    }

    @MainActor
    private func chooseExtension(_ ext: String) {
        XCTAssertTrue(scrollTo(extensionRow), "no Extension row")
        extensionRow.tap()
        tap(ext)
        XCTAssertTrue(extensionRow.waitForExistence(timeout: 5))
    }

    /// The name screen replaces Add and returns to the folder, so Back from
    /// there leaves Files.
    @MainActor
    func testAddsAFolder() {
        launch(at: "files/add", name: "projects")
        add("Folder", title: "New Folder")
        tap("Create")
        waitForTitle("Files")
        XCTAssertTrue(row("projects").exists)
        back()
        XCTAssertTrue(app.buttons["Files"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.staticTexts["Add"].exists)
    }

    @MainActor
    func testAddsASession() {
        launch(at: "files/add", name: "scratch")
        add("Session", title: "New Session")
        tap("Create")
        waitForTitle("Files")
        XCTAssertTrue(row("scratch.dial").exists)
    }

    /// A new file: the extension filled in, another chosen from the list, a
    /// refusal that a different extension clears, and the last extension used
    /// leading the list next time.
    @MainActor
    func testAddsAFile() {
        launch(at: "folder:notes", name: "notes")
        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        add("File", title: "New File")
        XCTAssertTrue(scrollTo(extensionRow))
        XCTAssertTrue(extensionRow.label.contains(".scm"), extensionRow.label)

        chooseExtension(".md")
        tap("Create")
        let refusal = text(containing: "An item named notes.md already exists")
        XCTAssertTrue(refusal.waitForExistence(timeout: 5))
        chooseExtension(".txt")
        XCTAssertFalse(refusal.exists, "the refusal outlived the extension it was about")
        tap("Create")
        waitForTitle("notes")
        XCTAssertTrue(row("notes.txt").exists)

        XCTAssertTrue(scrollTo(addButton, upFirst: true))
        addButton.tap()
        add("File", title: "New File")
        XCTAssertTrue(scrollTo(extensionRow))
        XCTAssertTrue(extensionRow.label.contains(".txt"), extensionRow.label)
        extensionRow.tap()
        let txt = app.buttons[".txt"]
        let scm = app.buttons[".scm"]
        XCTAssertTrue(txt.waitForExistence(timeout: 5))
        XCTAssertTrue(scm.exists)
        XCTAssertLessThan(txt.frame.minY, scm.frame.minY)
    }
}
