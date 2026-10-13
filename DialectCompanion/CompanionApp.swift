import SwiftUI

@main
struct CompanionApp: App {
    @State private var link = Self.startLink()

    var body: some Scene {
        WindowGroup {
            CompanionTabs()
                .environment(link)
        }
    }

    private static func startLink() -> PhoneLink {
        #if DEBUG
            if let facts = FakeWatch.facts() { return PhoneLink(facts: facts) }
        #endif
        let link = PhoneLink()
        link.start()
        return link
    }
}

enum CompanionTab: Hashable {
    case files
    case settings
    case watch
}

/// Files and Settings, then the watch's connection at the far right, tinted
/// with the watch's accent color.
struct CompanionTabs: View {
    @Environment(PhoneLink.self) private var link
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = CompanionTab.settings

    var body: some View {
        TabView(selection: $tab) {
            Tab("Files", systemImage: "folder", value: .files) {
                FilesTab()
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                NavigationStack {
                    SettingsScreen()
                }
            }
            Tab(value: .watch) {
                NavigationStack {
                    WatchScreen()
                }
            } label: {
                Label {
                    Text("Watch")
                } icon: {
                    Image(
                        uiImage: WatchTabIcon.image(
                            connected: link.status == .connected, selected: tab == .watch,
                            withoutColor: withoutColor, tint: UIColor(Color(accent)),
                            traits: iconTraits))
                }
                .accessibilityValue(link.status.map { Text(WatchScreen.title(of: $0)) } ?? Text(""))
            }
        }
        .tint(Color(accent))
        .onChange(of: scenePhase) { _, phase in
            // The app switcher makes the app inactive, and it can be quit from there.
            if phase != .active { link.flush() }
        }
    }

    /// The appearance the Watch tab's icon is drawn for.
    private var iconTraits: UITraitCollection {
        return UITraitCollection { traits in
            traits.userInterfaceStyle = colorScheme == .dark ? .dark : .light
            traits.accessibilityContrast = contrast == .increased ? .high : .normal
            traits.displayScale = displayScale
        }
    }

    /// The watch's accent color; Dialect's green until there's a snapshot.
    private var accent: RGBColor {
        return AccentSetting.color(from: link.snapshot?.value(AccentSetting.key)?.string ?? "")
    }
}
