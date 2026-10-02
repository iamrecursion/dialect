import SwiftUI

/// The accent color for the app.
enum AccentSetting {
    /// Its `UserDefaults` key; the value is in Display P3, as CSS writes it:
    /// `color(display-p3 0.5700 0.7800 0.5000)`.
    static let key = "accentColor"

    /// The stored value's color, defaulted if the setting is missing or
    /// corrupted. Before 2026-10-03 it was stored as sRGB hex, which is still
    /// read.
    static func color(from stored: String) -> RGBColor {
        return RGBColor(displayP3: stored) ?? RGBColor(hex: stored) ?? .dialectGreen
    }
}

extension Color {
    /// The list rows' fill on watchOS 27: (34, 34, 35), measured as there is no
    /// API for it. For things that should sit with the rows, such as the REPL's
    /// input field.
    static let listRowGray = Color(red: 34 / 255, green: 34 / 255, blue: 35 / 255)
}

extension EnvironmentValues {
    /// The app's accent color: set once at the root from the setting.
    @Entry var dialectAccent = Color(RGBColor.dialectGreen)
}

/// A menu or Settings row: the item's icon, tinted with the accent, then its
/// title. The button or list row around it supplies the system's gray
/// background.
struct MenuRowLabel: View {
    let item: MenuItem

    @Environment(\.dialectAccent) private var accent

    /// The icon's slot: icons are centered in it, so titles line up whatever
    /// each icon's width.
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 30

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: iconWidth)
            Text(item.title)
            Spacer(minLength: 0)
        }
    }
}
