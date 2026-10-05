import XCTest

/// What Files' UI tests share: launching on `-seedFiles`' sample tree, and
/// finding rows, screens and More's items.
class FilesUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = await XCUIApplication()
    }

    /// Launches on the sample tree with default settings, in US English by
    /// default: the simulator may be in British English, where the Trash is the
    /// Bin. `name` fills every name screen's field, as a UI test can't type
    /// into watchOS's text input.
    @MainActor
    func launch(
        at path: String? = nil, language: String = "en-US", name: String? = nil,
        arguments: [String] = []
    ) {
        app.launchArguments = [
            "-seedFiles", "YES", "-DialectResetSettings", "YES", "-AppleLanguages",
            "(\(language))",
        ]
        if let path {
            app.launchArguments += ["-DialectPath", path]
        }
        if let name {
            app.launchArguments += ["-DialectNameInput", name]
        }
        app.launchArguments += arguments
        app.launch()
    }

    /// The navigation bar's Back button.
    @MainActor
    func back() {
        app.navigationBars.buttons.firstMatch.tap()
    }

    /// A row's swipe from the right, then one of its buttons.
    @MainActor
    func swipeLeft(_ label: String, choose button: String) {
        let target = row(label)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "no row \(label)")
        target.swipeLeft()
        swipeAction(button, beside: target, of: label).tap()
    }

    /// A row's swipe from the left, then one of its buttons.
    @MainActor
    func swipeRight(_ label: String, choose button: String) {
        let target = row(label)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "no row \(label)")
        target.swipeRight()
        swipeAction(button, beside: target, of: label).tap()
    }

    /// The swipe's button with this label nearest the swiped row, as another
    /// button may share its label, such as the folder's More.
    @MainActor
    private func swipeAction(_ button: String, beside row: XCUIElement, of label: String)
        -> XCUIElement
    {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", button))
        XCTAssertTrue(
            matches.firstMatch.waitForExistence(timeout: 5), "no \(button) in \(label)'s swipe")
        let rowMiddle = row.frame.midY
        return matches.allElementsBoundByIndex.min {
            abs($0.frame.midY - rowMiddle) < abs($1.frame.midY - rowMiddle)
        } ?? matches.firstMatch
    }

    /// The row with this label, scrolled into view: a list builds only the rows
    /// on screen. It waits for the screen first.
    @MainActor
    func row(_ label: String) -> XCUIElement {
        let row = app.buttons[label]
        _ = app.collectionViews.firstMatch.waitForExistence(timeout: 5)
        _ = row.waitForExistence(timeout: 1)
        scrollTo(row)
        return row
    }

    /// Fails if a row with this label is anywhere in the list, looking down to
    /// its end and back up to its top.
    @MainActor
    func assertNoRow(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        _ = app.collectionViews.firstMatch.waitForExistence(timeout: 5)
        XCTAssertFalse(
            scrollTo(app.buttons[label], reportingMisses: false), "\(label) is listed",
            file: file, line: line)
    }

    @MainActor
    func open(_ label: String) {
        let target = row(label)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "no row \(label)")
        target.tap()
    }

    /// Waits for the navigation bar's title. A folder's row has its name too.
    @MainActor
    func waitForTitle(_ title: String) {
        XCTAssertTrue(
            app.navigationBars.staticTexts[title].waitForExistence(timeout: 5), "not on \(title)")
    }

    /// The element whose label contains this: Info's header and rows each read
    /// as one, such as "Created, 3 Oct 2026".
    @MainActor
    func text(containing value: String) -> XCUIElement {
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }

    /// Scrolls until `element` is on screen, looking toward the end of the list
    /// first, then back toward its top; `false` if it's in neither.
    ///
    /// It drags, as each crown turn waits about 6 s for the scrolling to settle
    /// and a drag takes about 2 s. A drag of under half a screen, held before
    /// it moves, leaves no momentum, so no row slips past unseen and a tap
    /// after it lands where it's aimed. The list ends when a drag changes
    /// nothing on screen. An element that exists but is out of reach, under the
    /// navigation bar or off the bottom, is brought in by short drags: a long
    /// drag can jump a list barely taller than the screen from its top to its
    /// end.
    @MainActor
    @discardableResult
    func scrollTo(
        _ element: XCUIElement, upFirst: Bool = false, reportingMisses: Bool = true
    ) -> Bool {
        for towardEnd in upFirst ? [false, true] : [true, false] {
            var last = ""
            for _ in 0..<40 {
                if isOnScreen(element) { return true }
                if element.exists && !element.frame.isEmpty {
                    // A nudge may take it out of the list.
                    for _ in 0..<6 where element.exists && !isOnScreen(element) {
                        drag(towardEnd: element.frame.midY > app.frame.midY, short: true)
                    }
                    if isOnScreen(element) { return true }
                }
                let now = screen()
                if now == last { break }
                last = now
                drag(towardEnd: towardEnd)
            }
        }
        if isOnScreen(element) { return true }
        if reportingMisses {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Screen when \(element) wasn't found"
            tree.lifetime = .keepAlways
            add(tree)
        }
        return false
    }

    /// Whether `element` is where a tap can reach it: below the navigation bar
    /// and within the screen. `isHittable` fails the test for a row scrolled
    /// out of reach on the 42 mm.
    @MainActor
    func isOnScreen(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard !frame.isEmpty else { return false }
        let top =
            app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 0
        return frame.midY > top && frame.midY < app.frame.maxY - 4
    }

    /// Everything on screen and where, without the element addresses, which
    /// change on every read. When a drag leaves it unchanged, the list is at
    /// its end.
    @MainActor
    private func screen() -> String {
        return app.debugDescription.replacingOccurrences(
            of: "0x[0-9a-f]+", with: "", options: .regularExpression)
    }

    /// Drags the content a little under half a screen, or a quarter when
    /// `short`: up to see further down (`towardEnd`), or down to see further
    /// up. It's slow and held still before letting go, as a drag released while
    /// moving flings the list, which then snaps a page at a time.
    @MainActor
    func drag(towardEnd: Bool, short: Bool = false) {
        // The app's frame: its first window may be the scroll indicator's sliver.
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: short ? 0.6 : 0.75))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: short ? 0.45 : 0.35))
        if towardEnd {
            low.press(
                forDuration: 0.05, thenDragTo: high, withVelocity: .slow, thenHoldForDuration: 0.2)
        } else {
            high.press(
                forDuration: 0.05, thenDragTo: low, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    /// Waits out a replace, which drops More from under its new screen after
    /// half a second: the system Back button lands on More before then.
    @MainActor
    func waitForReplace() {
        usleep(800_000)
    }

    @MainActor
    func longPress(_ label: String) {
        let target = row(label)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "no row \(label)")
        target.press(forDuration: 1.2)
        waitForTitle("More")
        // Info loads after the screen appears: the header's "Type · Size" line.
        XCTAssertTrue(text(containing: " · ").waitForExistence(timeout: 10), "no Info")
    }

    /// The folder's More button, then one of its items.
    @MainActor
    func folderMore(_ item: String) {
        let more = app.buttons["More"]
        // Back up to the buttons, which a list drops once scrolled past.
        XCTAssertTrue(scrollTo(more, upFirst: true), "no More")
        more.tap()
        waitForTitle("More")
        let target = app.buttons[item]
        XCTAssertTrue(scrollTo(target), "no \(item)")
        target.tap()
    }

    /// A choice on Sort or Group, once the folder's settings have loaded.
    @MainActor
    func choose(_ label: String) {
        // Every Sort and Group screen's first row; later ones may need scrolling to.
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label IN {'Name', 'None'}")).firstMatch
                .waitForExistence(timeout: 5))
        let choice = app.buttons[label]
        XCTAssertTrue(scrollTo(choice), "no \(label)")
        choice.tap()
    }
}
