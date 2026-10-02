import XCTest

/// The Accent Color setting end to end: a swatch sets the color, and Reset
/// restores the default.
@MainActor
final class AccentColorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Straight to the picker, and from the default whatever an earlier run left.
        app.launchArguments = [
            "-DialectPath", "settings/appearance/accent-color", "-DialectResetSettings", "YES",
        ]
        app.launch()
    }

    func testSwatchSetsTheColorAndResetRestoresIt() {
        let mint = app.buttons["Mint"]
        XCTAssertTrue(mint.waitForExistence(timeout: 5))
        mint.tap()
        XCTAssertTrue(hexField(showing: "#63E6E2"), "Mint did not set the hex")
        XCTAssertFalse(app.buttons[Self.notExact].exists, "Mint is inside sRGB")

        let reset = app.buttons["Reset to Default"]
        for _ in 0..<6 where !reset.isHittable {
            app.swipeUp()
        }
        reset.tap()
        XCTAssertTrue(hexField(showing: "#81C977"), "Reset did not restore the default")
    }

    /// The warning beside a hex value that is only the nearest to the color.
    private static let notExact = "Hex Not Exact"

    /// A color beyond sRGB shows the nearest hex, with a warning. Tapping it
    /// brings up an explanation comparing the two, like a notification, which
    /// Okay dismisses (Starfire).
    func testAColorBeyondSRGBShowsTheNearestHex() {
        launchWithAColorBeyondSRGB()
        XCTAssertTrue(hexField(showing: "#FF0000"), "no nearest hex")
        let warning = app.buttons[Self.notExact]
        XCTAssertTrue(warning.exists, "no warning that the hex is not exact")
        fingerTap(warning)
        let explanation = app.staticTexts["More vivid than sRGB hex can represent."]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5), "no explanation")
        XCTAssertTrue(app.staticTexts["Chosen"].exists, "no comparison")
        let okay = app.buttons["Okay"]
        XCTAssertTrue(okay.exists, "no Okay")
        fingerTap(okay)
        XCTAssertTrue(explanation.waitForNonExistence(timeout: 5), "Okay did not dismiss it")
        XCTAssertTrue(hexField(showing: "#FF0000"), "the color changed")
    }

    /// With the warning beside it, a finger on the hex field itself still opens
    /// the text input.
    func testTheHexFieldBesideTheWarningStillOpensTextInput() {
        launchWithAColorBeyondSRGB()
        XCTAssertTrue(hexField(showing: "#FF0000"), "no nearest hex")
        fingerTap(app.textFields.firstMatch)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "no text input")
    }

    /// Display P3's red, which sRGB does not have.
    private func launchWithAColorBeyondSRGB() {
        app.terminate()
        // Quoted, or the argument would be read as a property list. (A setting passed this way is
        // pinned for the run, which is fine here: nothing changes it.)
        app.launchArguments += ["-accentColor", "\"color(display-p3 1 0 0)\""]
        app.launch()
    }

    /// A tap where a finger would land: the middle of the element, as on
    /// screen. (`XCUIElement.tap` can reach an element a finger cannot.)
    private func fingerTap(_ element: XCUIElement) {
        let frame = element.frame
        let screen = app.frame
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: frame.midX / screen.width, dy: frame.midY / screen.height)
        ).tap()
    }

    /// The crown moves a slider slowly enough to dial a value in: Starfire
    /// found it too fast on the watch, still "extremely touchy" at three times
    /// slower. Unscaled, 0.3 of a turn moved the hue about 145° here; at three
    /// times, about 41°; at ten, it should be about 15°. The limit leaves room
    /// for simulated turns varying from run to run.
    func testTheCrownMovesASliderSlowly() throws {
        let hue = hueSlider()
        hue.tap()
        let before = try degrees(hue)
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.3)
        let moved = abs(try degrees(hue) - before)
        XCTAssertGreaterThan(moved, 0, "the crown did not move the hue")
        XCTAssertLessThanOrEqual(moved, 25, "the crown moved the hue \(moved)° for 0.3 of a turn")
    }

    /// Only one slider has the crown at a time: tapping another takes it over
    /// (Starfire found two focused at once on the watch).
    func testOnlyOneSliderHasTheCrown() throws {
        let hue = hueSlider()
        let saturation = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Saturation' AND value ENDSWITH ' percent'"))
            .firstMatch
        // Both on screen: Hue's row is just above Saturation's.
        for _ in 0..<4 where !(saturation.exists && saturation.isHittable) {
            drag(from: 0.7, to: 0.6)
        }
        XCTAssertTrue(hue.isHittable && saturation.isHittable)
        hue.tap()
        XCTAssertTrue(hue.isSelected, "the hue slider did not take the crown")
        saturation.tap()
        XCTAssertTrue(saturation.isSelected, "the saturation slider did not take the crown")
        XCTAssertFalse(hue.isSelected, "the hue slider kept the crown")

        let hueBefore = hue.value as? String
        let saturationBefore = saturation.value as? String
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.3)
        XCTAssertNotEqual(saturation.value as? String, saturationBefore, "saturation did not move")
        XCTAssertEqual(hue.value as? String, hueBefore, "hue moved too")
    }

    /// The hue slider, scrolled into view.
    private func hueSlider() -> XCUIElement {
        let hue = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Hue' AND value ENDSWITH ' degrees'"))
            .firstMatch
        for _ in 0..<12 where !(hue.exists && hue.isHittable) {
            drag(from: 0.75, to: 0.55)
        }
        return hue
    }

    /// A hue slider's value, "113 degrees", as 113.
    private func degrees(_ slider: XCUIElement) throws -> Int {
        let text = try XCTUnwrap(slider.value as? String)
        return try XCTUnwrap(Int(text.split(separator: " ")[0]))
    }

    /// A new accent reaches the rest of the app at once, not only after a
    /// relaunch: the menu's icons are drawn in it as soon as you go back.
    func testANewAccentReachesTheMenu() throws {
        app.buttons["Red"].tap()
        for _ in 0..<3 {
            app.navigationBars.buttons.firstMatch.tap()
        }
        let files = app.buttons["Files"]
        XCTAssertTrue(files.waitForExistence(timeout: 5))
        XCTAssertTrue(try contains(files, redPixels: true), "the menu's icons are not red")
    }

    /// Whether the element, as on screen now, has reddish pixels: red's icon
    /// against the gray.
    private func contains(_ element: XCUIElement, redPixels: Bool) throws -> Bool {
        let image = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
        let frame = element.frame
        let crop = CGRect(
            x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale,
            height: frame.height * scale)
        let region = try XCTUnwrap(image.cropping(to: crop))
        let width = region.width
        let height = region.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(region, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).contains { i in
            pixels[i] > 200 && pixels[i + 1] < 120 && pixels[i + 2] < 120
        }
    }

    /// Tapping a slider gives it the crown; tapping it again hands the crown
    /// back to the page.
    func testTappingASliderGivesAndTakesTheCrown() {
        // The slider, not its title text: the one whose value is in degrees.
        let hue = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Hue' AND value ENDSWITH ' degrees'"))
            .firstMatch
        // A finger scroll: simulated crown turns are too coarse to stop on one row.
        for _ in 0..<12 where !(hue.exists && hue.isHittable) {
            drag(from: 0.75, to: 0.55)
        }
        XCTAssertTrue(hue.isHittable)
        // Its readout: the default green's hue, in Display P3 (113° in sRGB).
        XCTAssertTrue(app.staticTexts["105°"].exists, "no hue readout")
        let before = hue.value as? String

        hue.tap()
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.3)
        let turned = hue.value as? String
        XCTAssertNotEqual(turned, before, "the crown did not move a focused slider")

        hue.tap()
        let top = hue.frame.minY
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.3)
        XCTAssertEqual(hue.value as? String, turned, "the crown moved a released slider")
        XCTAssertNotEqual(hue.frame.minY, top, "the crown did not scroll the page after release")

        // And a finger still scrolls it, even a swipe that starts on a slider.
        let afterCrown = hue.frame.minY
        // Upwards: there is always more below the sliders.
        drag(from: 0.7, to: 0.4)
        XCTAssertNotEqual(hue.frame.minY, afterCrown, "a finger did not scroll the page")
    }

    /// A short, slow vertical drag, held at its end so the list does not fling
    /// on, as fractions of the screen's height.
    private func drag(from start: CGFloat, to end: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Whether the hex field shows this value, scrolling down to it if needed.
    private func hexField(showing hex: String) -> Bool {
        let field = app.textFields.firstMatch
        // All of it on screen and below the navigation bar, where a finger can tap it. Small drags:
        // a swipe can carry it up under the bar.
        let top = app.frame.height * 0.25
        for _ in 0..<16 {
            if !field.exists || field.frame.maxY > app.frame.maxY {
                drag(from: 0.75, to: 0.55)
            } else if field.frame.minY < top {
                drag(from: 0.45, to: 0.6)
            } else {
                break
            }
        }
        return field.waitForExistence(timeout: 5) && (field.value as? String) == hex
    }
}
