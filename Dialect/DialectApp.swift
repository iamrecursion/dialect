import SwiftUI

@main
struct DialectApp: App {
    @State private var navigation = Navigation(path: Self.initialPath)
    @State private var fileSelection = FileSelection()
    @State private var binSelection = BinSelection()
    @State private var router = LaunchRouter.shared
    @AppStorage(AccentSetting.key) private var accent = RGBColor.dialectGreen.displayP3

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

            // For UI tests and screenshots: Files shows a fresh sample tree instead of Documents,
            // with separate stores.
            if UserDefaults.standard.bool(forKey: SeedFiles.argument) {
                do {
                    try SeedFiles.build(at: SeedFiles.root, stores: SeedFiles.stores)
                    FilesRoot.url = SeedFiles.root
                    FilesStores.url = SeedFiles.stores
                    FilesRoot.operations = FileOperations(
                        root: SeedFiles.root, stores: SeedFiles.stores)
                } catch {
                    assertionFailure("Couldn't build the sample files: \(error)")
                }
            }
        #endif

        // Whatever was being made or shared when Dialect last stopped is abandoned.
        let operations = FilesRoot.operations
        let stores = FilesStores.url
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
            .onChange(of: navigation.path) { _, path in
                fileSelection.follow(path)
                binSelection.follow(path)
            }
            .onOpenURL { router.open($0) }
            .onChange(of: router.pending, initial: true) { followLaunch() }
        }
    }

    /// Goes where a launch request asks, if one is waiting.
    private func followLaunch() {
        guard let request = router.take() else { return }
        navigation.path = LaunchRouter.path(
            for: request, hasLatestSession: FakeSessions.hasLatestSession())
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
