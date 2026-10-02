import SwiftUI

/// Settings > Appearance.
struct AppearanceView: View {
    static let rows = [
        MenuItem(title: "Accent Color", systemImage: "swatchpalette", route: .accentColor)
    ]

    @Environment(\.dialectAccent) private var accent

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
        }
        .navigationTitle("Appearance")
    }
}

#Preview {
    NavigationStack {
        AppearanceView()
    }
}
