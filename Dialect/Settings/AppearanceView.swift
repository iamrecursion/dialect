import SwiftUI

/// Settings > Appearance.
struct AppearanceView: View {
    static let rows = [
        MenuItem(title: "Accent Color", systemImage: "swatchpalette", route: .accentColor)
    ]

    @Environment(\.dialectAccent) private var accent
    @AppStorage(FileSettings.dateStyleKey) private var dateStyle = FileSettings.dateStyleDefault
    @AppStorage(FileSettings.use24HourKey) private var use24Hour = FileSettings.use24HourDefault

    var body: some View {
        List {
            ForEach(Self.rows) { item in
                NavigationLink(value: item.route) {
                    HStack {
                        MenuRowLabel(item: item)
                        // The current color, as well as the icon drawn in it.
                        Circle()
                            .fill(accent)
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                    }
                }
            }
            // How Files shows dates and times.
            Section {
                Picker("Dates", selection: $dateStyle) {
                    ForEach(DateStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.navigationLink)
                Toggle("Use 24-Hour Time", isOn: $use24Hour)
            }
        }
        .navigationTitle("Appearance")
    }
}

#Preview {
    NavigationStack {
        AppearanceView()
    }
}
