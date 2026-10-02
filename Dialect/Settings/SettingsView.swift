import SwiftUI

/// Settings: one row per group of settings, then Credits on its own at the
/// bottom.
struct SettingsView: View {
    static let rows = [
        MenuItem(title: "Editor", systemImage: "keyboard", route: .editorSettings),
        MenuItem(
            title: "Sessions", systemImage: "document.badge.gearshape", route: .sessionSettings),
        MenuItem(title: "Appearance", systemImage: "paintpalette", route: .appearanceSettings),
        MenuItem(
            title: "Runtime", systemImage: "gauge.with.dots.needle.100percent",
            route: .runtimeSettings),
        MenuItem(title: "Files", systemImage: "folder.badge.gearshape", route: .fileSettings),
        MenuItem(
            title: "Downloader", systemImage: "arrow.down.circle.dotted",
            route: .downloaderSettings),
        MenuItem(
            title: "Companion", systemImage: "ipad.landscape.and.applewatch",
            route: .companionSettings),
    ]

    static let credits = MenuItem(title: "Credits", systemImage: "list.clipboard", route: .credits)

    @AppStorage(FakeSessions.key) private var pretendSessionExists = false

    var body: some View {
        List {
            Section {
                ForEach(Self.rows) { item in
                    NavigationLink(value: item.route) {
                        MenuRowLabel(item: item)
                    }
                }
            }
            Section {
                NavigationLink(value: Self.credits.route) {
                    MenuRowLabel(item: Self.credits)
                }
            }
            #if DEBUG
                Section("Developer") {
                    // Until sessions exist: try both ways Resume or New can go.
                    Toggle("Pretend a session exists", isOn: $pretendSessionExists)
                    NavigationLink("Complications") { ComplicationGallery() }
                }
            #endif
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
