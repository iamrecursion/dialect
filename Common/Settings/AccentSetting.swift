import Foundation

/// The accent color for the app.
enum AccentSetting {
    /// Its `UserDefaults` key; the value is in Display P3, as CSS writes it:
    /// `color(display-p3 0.5700 0.7800 0.5000)`.
    static let key = "accentColor"

    /// The stored value's color, defaulted if the setting is missing or
    /// corrupted. Older settings stored it as sRGB hex, which is still read.
    static func color(from stored: String) -> RGBColor {
        return RGBColor(displayP3: stored) ?? RGBColor(hex: stored) ?? .dialectGreen
    }
}
