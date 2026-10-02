import SwiftUI
import Testing

@testable import Dialect

struct RGBColorTests {
    @Test(arguments: [
        ("#81C977", RGBColor(sRGBRed: 0x81, green: 0xC9, blue: 0x77)),
        ("81c977", RGBColor(sRGBRed: 0x81, green: 0xC9, blue: 0x77)),
        ("  #81c977\n", RGBColor(sRGBRed: 0x81, green: 0xC9, blue: 0x77)),
        ("#8C7", RGBColor(sRGBRed: 0x88, green: 0xCC, blue: 0x77)),
        ("fff", RGBColor(sRGBRed: 0xFF, green: 0xFF, blue: 0xFF)),
    ])
    func parsesHex(_ text: String, _ color: RGBColor) {
        #expect(RGBColor(hex: text) == color)
    }

    @Test(arguments: ["", "#", "#12345", "#1234567", "#81C977FF", "#GGGGGG", "81 C977", "##81C977"])
    func rejectsWhatIsNotHex(_ text: String) {
        #expect(RGBColor(hex: text) == nil)
    }

    @Test func formatsAsUppercaseHex() {
        #expect(RGBColor(sRGBRed: 0x0A, green: 0x84, blue: 0xFF).hex == "#0A84FF")
    }

    /// The green as first chosen, `display-p3(0.57, 0.78, 0.50)`, exactly. It
    /// is inside sRGB, where it is `#81C977`.
    @Test func defaultIsDialectGreen() {
        #expect(RGBColor.dialectGreen == RGBColor(red: 0.57, green: 0.78, blue: 0.5))
        #expect(RGBColor.dialectGreen.hex == "#81C977")
        #expect(RGBColor.dialectGreen.isWithinSRGB)
    }

    /// Hex is sRGB, as everywhere else people find it, so a hex color is
    /// converted into Display P3.
    @Test func convertsSRGBIntoDisplayP3() {
        #expect(
            RGBColor(sRGBRed: 0x63, green: 0xE6, blue: 0xE2)
                == RGBColor(red: 0.5302, green: 0.8907, blue: 0.8818))
        #expect(
            RGBColor(sRGBRed: 0xFF, green: 0x45, blue: 0x3A)
                == RGBColor(red: 0.9227, green: 0.3331, blue: 0.2715))
    }

    /// Typing a hex value shows the same value back, whatever it is.
    @Test func everyHexRoundTrips() {
        for red in stride(from: 0, through: 255, by: 5) {
            for green in stride(from: 0, through: 255, by: 5) {
                for blue in stride(from: 0, through: 255, by: 5) {
                    let hex = String(format: "#%02X%02X%02X", red, green, blue)
                    let color = RGBColor(hex: hex)
                    #expect(color?.hex == hex)
                    #expect(color?.isWithinSRGB == true, "\(hex)")
                }
            }
        }
    }

    /// Display P3 reaches further than sRGB: hex shows the nearest it can.
    @Test func showsTheNearestHexForAColorBeyondSRGB() {
        let red = RGBColor(red: 1, green: 0, blue: 0)
        #expect(!red.isWithinSRGB)
        #expect(red.hex == "#FF0000")
        let green = RGBColor(red: 0, green: 1, blue: 0)
        #expect(!green.isWithinSRGB)
        #expect(green.hex == "#00FF00")
        #expect(red.nearestInSRGB == RGBColor(sRGBRed: 0xFF, green: 0, blue: 0))
        #expect(RGBColor.dialectGreen.nearestInSRGB == RGBColor(hex: "#81C977"))
    }

    /// Submitting the hex field unchanged keeps the color, even one beyond sRGB
    /// that its hex only comes near.
    @Test func applyingItsOwnHexKeepsTheColor() {
        let vivid = RGBColor(red: 1, green: 0, blue: 0)
        #expect(vivid.applyingHex("#FF0000") == vivid)
        #expect(vivid.applyingHex(" #ff0000 ") == vivid)
        #expect(vivid.applyingHex("#FF0001") == RGBColor(sRGBRed: 0xFF, green: 0, blue: 1))
        #expect(vivid.applyingHex("red") == nil)
    }

    /// Components are kept in Display P3's range, to four decimal places, so a
    /// color written down and read back is the same color.
    @Test func roundsAndClampsComponents() {
        #expect(
            RGBColor(red: 1.2, green: -0.1, blue: 0.123456)
                == RGBColor(red: 1, green: 0, blue: 0.1235))
    }

    @Test func writesDisplayP3InCSSSyntax() {
        #expect(RGBColor.dialectGreen.displayP3 == "color(display-p3 0.5700 0.7800 0.5000)")
    }

    @Test func readsDisplayP3Back() {
        let colors =
            RGBColor.swatches.map(\.color) + [
                RGBColor(red: 1, green: 0, blue: 0), RGBColor(red: 0.0001, green: 0.9999, blue: 0),
            ]
        for color in colors {
            #expect(RGBColor(displayP3: color.displayP3) == color, "\(color.displayP3)")
        }
        #expect(
            RGBColor(displayP3: " color(display-p3  1 0.5 0) ")
                == RGBColor(red: 1, green: 0.5, blue: 0))
    }

    @Test(arguments: [
        "", "#81C977", "color(display-p3 1 0)", "color(display-p3 1 0 0 0)", "color(srgb 1 0 0)",
        "color(display-p3 1 0 x)", "color(display-p3 1 0 0", "display-p3 1 0 0",
    ])
    func rejectsWhatIsNotDisplayP3(_ text: String) {
        #expect(RGBColor(displayP3: text) == nil)
    }

    /// SwiftUI is given the color in Display P3, so it can draw colors beyond
    /// sRGB: as extended sRGB, Display P3's red is redder than sRGB's.
    @Test func drawsInDisplayP3() {
        let resolved = Color(RGBColor(red: 1, green: 0, blue: 0)).resolve(in: EnvironmentValues())
        #expect(resolved.red > 1.01)
        #expect(resolved.green < 0)
    }

    @Test func convertsToHueSaturationBrightness() {
        let red = RGBColor(red: 1, green: 0, blue: 0).hsb(fallbackHue: 0.5)
        #expect(red == HSB(hue: 0, saturation: 1, brightness: 1))
        let blue = RGBColor(red: 0, green: 0, blue: 1).hsb(fallbackHue: 0)
        #expect(abs(blue.hue - 2.0 / 3) < 1e-9)
    }

    /// A gray or black has no hue of its own, so the caller's is kept: a slider
    /// set to a hue is not thrown back to red by picking a gray.
    @Test func grayKeepsTheFallbackHue() {
        let gray = RGBColor(red: 0.5, green: 0.5, blue: 0.5).hsb(fallbackHue: 0.3)
        #expect(gray.hue == 0.3)
        #expect(gray.saturation == 0)
        #expect(RGBColor(red: 0, green: 0, blue: 0).hsb(fallbackHue: 0.7).hue == 0.7)
    }

    @Test func roundTripsThroughHueSaturationBrightness() {
        let colors =
            RGBColor.swatches.map(\.color) + [
                RGBColor(red: 0, green: 0, blue: 0), RGBColor(red: 1, green: 1, blue: 1),
                RGBColor(red: 0.0039, green: 0.0078, blue: 0.0118),
                RGBColor(red: 0.9961, green: 0, blue: 0.498),
            ]
        for color in colors {
            #expect(RGBColor(color.hsb(fallbackHue: 0)) == color, "\(color.displayP3)")
        }
    }

    @Test func swatchesAreUniqueAndStartWithTheDefault() {
        let colors = RGBColor.swatches.map(\.color)
        #expect(colors.count == 12)
        #expect(colors.first == .dialectGreen)
        #expect(Set(colors).count == colors.count)
    }

    /// The swatches are Apple's dark-mode system colors (and a lavender), which
    /// are given in sRGB: in Display P3 they look the same as they did.
    @Test func swatchesKeepTheirSRGBLook() {
        #expect(
            RGBColor.swatches.map(\.color.hex) == [
                "#81C977", "#63E6E2", "#40C8E0", "#64D2FF", "#0A84FF", "#9D9BFF", "#BF5AF2",
                "#FF375F", "#FF453A", "#FF9F0A", "#FFD60A", "#AC8E68",
            ])
    }

    /// VoiceOver reads a swatch by its name.
    @Test func swatchesHaveUniqueNames() {
        let names = RGBColor.swatches.map(\.name.key)
        #expect(names.first == "Green")
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    /// WCAG's 3:1 for graphics, against the list rows' gray, so every swatch
    /// reads as an icon.
    @Test func everySwatchReadsOnTheRowGray() {
        let rowGray = RGBColor(sRGBRed: 34, green: 34, blue: 35)
        for swatch in RGBColor.swatches {
            #expect(swatch.color.contrast(with: rowGray) >= 3, "\(swatch.name.key)")
        }
    }

    @Test func contrastMatchesWCAG() {
        let black = RGBColor(red: 0, green: 0, blue: 0)
        let white = RGBColor(red: 1, green: 1, blue: 1)
        #expect(abs(black.contrast(with: white) - 21) < 1e-6)
        #expect(white.contrast(with: white) == 1)
        // WCAG's own example pair: #767676 on white is 4.54:1.
        let gray = RGBColor(sRGBRed: 0x76, green: 0x76, blue: 0x76)
        #expect(abs(gray.contrast(with: white) - 4.54) < 0.01)
    }
}
