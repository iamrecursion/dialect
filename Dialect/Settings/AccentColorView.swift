import SwiftUI

/// Settings > Appearance > Accent Color: the app's accent color.
struct AccentColorView: View {
    @AppStorage(AccentSetting.key) private var stored = RGBColor.dialectGreen.displayP3

    var body: some View {
        ColorPicker(
            color: Binding(
                get: { AccentSetting.color(from: stored) }, set: { stored = $0.displayP3 }),
            defaultColor: .dialectGreen
        ) { color in
            // A menu row, as the accent appears in the app.
            MenuRowLabel(
                item: MenuItem(title: "Preview", systemImage: "square.and.pencil", route: .newREPL)
            )
            .environment(\.dialectAccent, color)
        }
        .navigationTitle("Accent Color")
    }
}

#Preview {
    NavigationStack {
        AccentColorView()
    }
}
