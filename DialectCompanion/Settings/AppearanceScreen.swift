import SwiftUI

/// The watch's Settings › Appearance.
struct AppearanceScreen: View {
    @Environment(PhoneLink.self) private var link

    var body: some View {
        List {
            if let stored = link.value(AccentSetting.key)?.string {
                NavigationLink {
                    AccentColorScreen()
                } label: {
                    AccentColorRow(color: AccentSetting.color(from: stored))
                }
            }
            Section {
                SettingPicker(
                    title: "Dates", key: FileSettings.dateStyleKey, choices: DateStyle.allCases
                ) { Text($0.title) }
                SettingToggle(title: "Use 24-Hour Time", key: FileSettings.use24HourKey)
            }
        }
        .navigationTitle("Appearance")
    }
}

/// The accent color, and its swatch's name or Custom.
private struct AccentColorRow: View {
    let color: RGBColor

    var body: some View {
        LabeledContent {
            HStack {
                Circle()
                    .fill(Color(color))
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                if let swatch = RGBColor.swatches.first(where: { $0.color == color }) {
                    Text(swatch.name)
                } else {
                    Text("Custom")
                }
            }
        } label: {
            Label {
                SettingTitle(title: "Accent Color", key: AccentSetting.key)
            } icon: {
                Image(systemName: "swatchpalette")
                    .foregroundStyle(.tint)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceScreen()
    }
    .environment(PhoneLink())
}
