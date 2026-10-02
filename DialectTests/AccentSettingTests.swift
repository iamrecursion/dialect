import Testing

@testable import Dialect

struct AccentSettingTests {
    @Test func readsAStoredColor() {
        #expect(
            AccentSetting.color(from: "color(display-p3 0.5302 0.8907 0.8818)")
                == RGBColor(red: 0.5302, green: 0.8907, blue: 0.8818))
    }

    /// The setting was stored as sRGB hex until 2026-10-03.
    @Test func readsAnOlderHexColor() {
        #expect(
            AccentSetting.color(from: "#63E6E2")
                == RGBColor(sRGBRed: 0x63, green: 0xE6, blue: 0xE2))
    }

    /// A missing or damaged setting must not leave the app without an accent.
    @Test(arguments: ["", "green", "#12345", "color(display-p3 1 0)"])
    func readsAnythingElseAsTheDefault(_ stored: String) {
        #expect(AccentSetting.color(from: stored) == .dialectGreen)
    }
}
