import SwiftUI
import WatchConnectivity

@main
struct CompanionApp: App {
    @State private var services = Self.start()

    var body: some Scene {
        WindowGroup {
            CompanionTabs()
                .environment(services.link)
                .environment(services.files)
        }
    }

    /// The link and Files, against the fake watch if the launch arguments say
    /// so.
    private static func start() -> (link: PhoneLink, files: WatchFiles) {
        #if DEBUG
            if let facts = FakeWatch.facts() {
                let link = PhoneLink(facts: facts, watchDirectory: FakeWatch.cacheDirectory)
                return (link, FakeWatch.files())
            }
        #endif
        let connection = LiveFilesConnection(session: WCSession.default)
        let link = PhoneLink()
        link.start(
            filesAnswers: { connection.deliver($0) },
            reachability: { connection.reachabilityChanged($0) })
        return (link, WatchFiles(connection: connection))
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
    @Environment(WatchFiles.self) private var files
    @State private var tab = CompanionTab.files

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
        .onChange(of: filesState, initial: true) { _, state in
            files.follow(state)
        }
        .onChange(of: scenePhase) { _, phase in
            // The app switcher makes the app inactive, and it can be quit from there.
            if phase != .active { link.flush() }
            if phase == .active { files.becameActive() }
        }
    }

    /// What Files needs of the link.
    private var filesState: FilesLinkState {
        return FilesLinkState(
            status: link.status, isReachable: link.facts?.isReachable ?? false,
            epoch: link.snapshot?.epoch,
            directory: link.watchDirectory,
            display: FilesDisplay(value: link.value))
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
