import SwiftUI

@main
struct DialectApp: App {
    @State private var navigation = Navigation(path: Self.initialPath)
    @State private var fileSelection = FileSelection()
    @State private var binSelection = BinSelection()
    @State private var router = LaunchRouter.shared
    @AppStorage(AccentSetting.key) private var accent = RGBColor.dialectGreen.displayP3
    @Environment(\.scenePhase) private var scenePhase
    private let operations: FileOperations
    private let link: WatchLink

    init() {
        #if DEBUG
            // For UI tests: start from default settings as passing a setting as a launch argument
            // instead would pin it: arguments outrank anything the app saves.
            if UserDefaults.standard.bool(forKey: "DialectResetSettings"),
                let domain = Bundle.main.bundleIdentifier
            {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }

            // For UI tests: a link as if a complication had opened it. watchOS will not open a
            // third-party scheme from outside the app (`simctl openurl`, `XCUIApplication.open`
            // both fail), but a complication's link reaches `onOpenURL` directly.
            if let link = UserDefaults.standard.string(forKey: "DialectOpenURL"),
                let url = URL(string: link)
            {
                LaunchRouter.shared.open(url)
            }
        #endif

        let files = Self.filesLocation()
        let operations = FileOperations(root: files.root, stores: files.stores)
        self.operations = operations
        link = WatchLink(operations: operations)
        link.start()

        // Whatever was being made or shared when Dialect last stopped is abandoned.
        let stores = operations.stores
        let emptyTrashAfter = FileSettings.emptyTrashAfter()
        Task.detached(priority: .background) {
            Sharing.clear(in: stores)
            await operations.clearStaging()
            await operations.removeExpired(after: emptyTrashAfter)
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $navigation.path) {
                MainMenu(path: $navigation.path)
                    .navigationDestination(for: Route.self) { route in
                        route.destination
                    }
            }
            .environment(\.dialectAccent, Color(AccentSetting.color(from: accent)))
            .environment(navigation)
            .environment(fileSelection)
            .environment(binSelection)
            .fileOperations(operations)
            .onChange(of: navigation.path) { _, path in
                fileSelection.follow(path)
                binSelection.follow(path)
            }
            .onOpenURL { router.open($0) }
            // Sends what changes without a settings change, such as the undo history's length.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { link.publish() }
            }
            .onChange(of: router.pending, initial: true) { followLaunch() }
        }
        // The phone's edits, delivered while Dialect isn't open.
        .backgroundTask(.watchConnectivity) { [link] in
            await link.waitForDelivery()
        }
    }

    /// Goes where a launch request asks, if one is waiting.
    private func followLaunch() {
        guard let request = router.take() else { return }
        navigation.path = LaunchRouter.path(
            for: request, hasLatestSession: FakeSessions.hasLatestSession())
    }

    /// Files' root and stores: Documents, or for UI tests and screenshots under
    /// `-seedFiles`, a fresh sample tree with separate stores.
    private static func filesLocation() -> (root: URL, stores: URL) {
        #if DEBUG
            if UserDefaults.standard.bool(forKey: SeedFiles.argument) {
                do {
                    try SeedFiles.build(at: SeedFiles.root, stores: SeedFiles.stores)
                    return (SeedFiles.root, SeedFiles.stores)
                } catch {
                    assertionFailure("Couldn't build the sample files: \(error)")
                }
            }
        #endif
        return (.documentsDirectory, FilesStores.standard)
    }

    /// Empty, except in a debug build launched with `-DialectPath` (see
    /// `Route.debugPath`).
    private static var initialPath: [Route] {
        #if DEBUG
            if let spec = UserDefaults.standard.string(forKey: "DialectPath") {
                return Route.debugPath(spec, creditsPages: NoticeDocument.creditsPages(in: .main))
            }
        #endif
        return []
    }
}
