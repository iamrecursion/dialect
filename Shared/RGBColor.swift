import Foundation
import SwiftUI

/// A color as Dialect stores it: Display P3, the watch's own color space, so a
/// color can be more vivid than sRGB allows.
///
/// Hex is conventionally sRGB so a hex color is converted into Display P3, and
/// a color is shown as hex by the nearest sRGB color (`isWithinSRGB` says
/// whether that is exact, to 8 bits). Stored as CSS writes it,
/// `color(display-p3 0.5700 0.7800 0.5000)`.
///
/// Components are rounded to four decimal places: fine enough that every hex
/// color comes back as the same hex, and coarse enough that a color written
/// down and read back is equal to what was written.
struct RGBColor: Hashable, Sendable {
    /// Display P3's components, each in `0...1`.
    let red: Double
    let green: Double
    let blue: Double

    /// Display P3's components, clamped to `0...1`.
    init(red: Double, green: Double, blue: Double) {
        func component(_ value: Double) -> Double {
            return (min(max(value, 0), 1) * 10_000).rounded() / 10_000
        }
        self.red = component(red)
        self.green = component(green)
        self.blue = component(blue)
    }

    /// Dialect's green, `display-p3(0.57, 0.78, 0.50)` as first chosen. It is
    /// inside sRGB, where it is `#81C977`.
    static let dialectGreen = RGBColor(red: 0.57, green: 0.78, blue: 0.50)

    /// The color picker's swatches: the default first, then the rest by hue.
    ///
    /// Each reads as an icon on the list rows' gray (at least WCAG's 3:1 for
    /// graphics; mostly Apple's dark-mode system colors, given in sRGB, with a
    /// lighter lavender for indigo for better contrast).
    static let swatches: [NamedColor] = [
        NamedColor(name: "Green", color: .dialectGreen),
        NamedColor(name: "Mint", color: RGBColor(sRGBRed: 0x63, green: 0xE6, blue: 0xE2)),
        NamedColor(name: "Teal", color: RGBColor(sRGBRed: 0x40, green: 0xC8, blue: 0xE0)),
        NamedColor(name: "Cyan", color: RGBColor(sRGBRed: 0x64, green: 0xD2, blue: 0xFF)),
        NamedColor(name: "Blue", color: RGBColor(sRGBRed: 0x0A, green: 0x84, blue: 0xFF)),
        NamedColor(name: "Lavender", color: RGBColor(sRGBRed: 0x9D, green: 0x9B, blue: 0xFF)),
        NamedColor(name: "Purple", color: RGBColor(sRGBRed: 0xBF, green: 0x5A, blue: 0xF2)),
        NamedColor(name: "Pink", color: RGBColor(sRGBRed: 0xFF, green: 0x37, blue: 0x5F)),
        NamedColor(name: "Red", color: RGBColor(sRGBRed: 0xFF, green: 0x45, blue: 0x3A)),
        NamedColor(name: "Orange", color: RGBColor(sRGBRed: 0xFF, green: 0x9F, blue: 0x0A)),
        NamedColor(name: "Yellow", color: RGBColor(sRGBRed: 0xFF, green: 0xD6, blue: 0x0A)),
        NamedColor(name: "Brown", color: RGBColor(sRGBRed: 0xAC, green: 0x8E, blue: 0x68)),
    ]
}

// sRGB, as hex.
extension RGBColor {
    /// An sRGB color, 8 bits a channel.
    init(sRGBRed red: UInt8, green: UInt8, blue: UInt8) {
        let linear = ColorSpace.linear((Double(red) / 255, Double(green) / 255, Double(blue) / 255))
        let encoded = ColorSpace.encoded(ColorSpace.sRGBToP3.applied(to: linear))
        self.init(red: encoded.0, green: encoded.1, blue: encoded.2)
    }

    /// An sRGB color as `#RRGGBB` or `#RGB`, the `#` optional, any case,
    /// surrounding whitespace ignored; `nil` for anything else.
    init?(hex: String) {
        var digits = Substring(hex.trimmingCharacters(in: .whitespacesAndNewlines))
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        switch digits.count {
        case 6: break
        case 3: digits = Substring(digits.flatMap { [$0, $0] })
        default: return nil
        }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            sRGBRed: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF),
            blue: UInt8(value & 0xFF))
    }

    /// The nearest sRGB color as `#RRGGBB`: exactly this color, to 8 bits, if
    /// `isWithinSRGB`; otherwise this color clipped to sRGB.
    var hex: String {
        let (red, green, blue) = sRGBChannels
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// The color `hex` shows.
    var nearestInSRGB: RGBColor {
        let (red, green, blue) = sRGBChannels
        return RGBColor(sRGBRed: red, green: green, blue: blue)
    }

    /// Whether sRGB has this color, to 8 bits: whether `hex` is exact.
    var isWithinSRGB: Bool {
        let sRGB = self.sRGB
        let range = -0.5 / 255...1 + 0.5 / 255
        return range.contains(sRGB.0) && range.contains(sRGB.1) && range.contains(sRGB.2)
    }

    /// What a hex field's text makes this color, or `nil` if it is not hex.
    func applyingHex(_ text: String) -> RGBColor? {
        guard let parsed = RGBColor(hex: text) else { return nil }
        return parsed.hex == hex ? self : parsed
    }

    /// The nearest sRGB color's 8-bit channels: this color clipped to sRGB.
    private var sRGBChannels: (UInt8, UInt8, UInt8) {
        func channel(_ value: Double) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
        let sRGB = self.sRGB
        return (channel(sRGB.0), channel(sRGB.1), channel(sRGB.2))
    }

    /// This color in sRGB, extended beyond `0...1` for colors sRGB does not
    /// have.
    private var sRGB: ColorSpace.Components {
        return ColorSpace.encoded(
            ColorSpace.p3ToSRGB.applied(to: ColorSpace.linear((red, green, blue))))
    }
}

// Display P3, as text.
extension RGBColor {
    /// As CSS writes it: `color(display-p3 0.5700 0.7800 0.5000)`.
    var displayP3: String {
        return String(format: "color(display-p3 %.4f %.4f %.4f)", red, green, blue)
    }

    /// CSS's `color(display-p3 r g b)`, each component a number; `nil` for
    /// anything else.
    init?(displayP3 text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("color("), text.hasSuffix(")") else { return nil }
        let words = text.dropFirst("color(".count).dropLast().split(whereSeparator: \.isWhitespace)
        guard words.count == 4, words[0] == "display-p3" else { return nil }
        let components = words.dropFirst().compactMap { Double($0) }.filter(\.isFinite)
        guard components.count == 3 else { return nil }
        self.init(red: components[0], green: components[1], blue: components[2])
    }
}

// Hue, saturation and brightness, and contrast.
extension RGBColor {
    /// The color at this hue, saturation and brightness, each in `0...1`, in
    /// Display P3: full saturation reaches beyond sRGB.
    init(_ hsb: HSB) {
        let hue = (hsb.hue - hsb.hue.rounded(.down)) * 6
        let sector = Int(hue) % 6
        let fraction = hue - hue.rounded(.down)
        let v = hsb.brightness
        let p = v * (1 - hsb.saturation)
        let q = v * (1 - hsb.saturation * fraction)
        let t = v * (1 - hsb.saturation * (1 - fraction))
        let (r, g, b): (Double, Double, Double) =
            switch sector {
            case 0: (v, t, p)
            case 1: (q, v, p)
            case 2: (p, v, t)
            case 3: (p, q, v)
            case 4: (t, p, v)
            default: (v, p, q)
            }
        self.init(red: r, green: g, blue: b)
    }

    /// Hue, saturation and brightness, each in `0...1`. A gray or black has no
    /// hue of its own, so it takes `fallbackHue` (and a black keeps saturation
    /// 0).
    func hsb(fallbackHue: Double) -> HSB {
        let (r, g, b) = (red, green, blue)
        let maximum = max(r, g, b)
        let delta = maximum - min(r, g, b)
        guard delta > 0 else { return HSB(hue: fallbackHue, saturation: 0, brightness: maximum) }
        let hue: Double =
            if maximum == r {
                ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximum == g {
                (b - r) / delta + 2
            } else {
                (r - g) / delta + 4
            }
        return HSB(
            hue: (hue / 6 + 1).truncatingRemainder(dividingBy: 1), saturation: delta / maximum,
            brightness: maximum)
    }

    /// WCAG's contrast ratio, from 1 (none) to 21 (black on white).
    func contrast(with other: RGBColor) -> Double {
        let (lighter, darker) =
            (max(luminance, other.luminance), min(luminance, other.luminance))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Relative luminance, as WCAG defines it for sRGB, but from Display P3's
    /// own primaries, so it holds beyond sRGB too.
    private var luminance: Double {
        let linear = ColorSpace.linear((red, green, blue))
        let y = ColorSpace.p3Luminance
        return y.0 * linear.0 + y.1 * linear.1 + y.2 * linear.2
    }
}

/// The arithmetic between sRGB and Display P3. Both have D65 white and sRGB's
/// transfer function, and differ in their primaries.
private enum ColorSpace {
    typealias Components = (Double, Double, Double)

    /// A 3×3 matrix, by rows, between linear components.
    struct Matrix {
        let rows: (Components, Components, Components)

        func applied(to c: Components) -> Components {
            func row(_ r: Components) -> Double { r.0 * c.0 + r.1 * c.1 + r.2 * c.2 }
            return (row(rows.0), row(rows.1), row(rows.2))
        }
    }

    // Derived from each space's primaries and white point (sRGB: IEC 61966-2-1;
    // Display P3: DCI-P3's primaries with D65 white).
    static let p3ToSRGB = Matrix(
        rows: (
            (1.2249401762805596, -0.22494017628055982, 0),
            (-0.04205695470968815, 1.042056954709688, 0),
            (-0.01963755459033444, -0.07863604555063183, 1.0982736001409665)
        ))
    static let sRGBToP3 = Matrix(
        rows: (
            (0.8224619687143622, 0.17753803128563778, 0),
            (0.03319419885096161, 0.9668058011490384, 0),
            (0.01708263072112004, 0.07239744066396342, 0.9105199286149165)
        ))
    /// Display P3's row of its matrix to CIE XYZ: luminance from linear
    /// components.
    static let p3Luminance: Components = (
        0.22897456406974873, 0.6917385218365063, 0.079286914093745
    )

    /// From encoded components to linear light, extended to negative values by
    /// symmetry, as Apple's extended color spaces do.
    static func linear(_ c: Components) -> Components {
        func one(_ value: Double) -> Double {
            let magnitude = abs(value)
            let linear =
                magnitude <= 0.04045 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
            return value < 0 ? -linear : linear
        }
        return (one(c.0), one(c.1), one(c.2))
    }

    /// From linear light to encoded components, extended as `linear` is.
    static func encoded(_ c: Components) -> Components {
        func one(_ value: Double) -> Double {
            let magnitude = abs(value)
            let encoded =
                magnitude <= 0.0031308 ? magnitude * 12.92 : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
            return value < 0 ? -encoded : encoded
        }
        return (one(c.0), one(c.1), one(c.2))
    }
}

/// A color with a name, so VoiceOver has something to read for a swatch.
struct NamedColor: Identifiable, Equatable, Sendable {
    /// Localizable, and so not hashable: swatches are identified by their
    /// color.
    let name: LocalizedStringResource
    let color: RGBColor

    var id: RGBColor { color }
}

/// Hue, saturation and brightness, each in `0...1`.
struct HSB: Hashable, Sendable {
    var hue: Double
    var saturation: Double
    var brightness: Double
}

extension Color {
    init(_ color: RGBColor) {
        self.init(.displayP3, red: color.red, green: color.green, blue: color.blue)
    }
}
