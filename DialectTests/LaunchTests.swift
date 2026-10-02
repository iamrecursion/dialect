import Foundation
import Testing

@testable import Dialect

struct LaunchRequestTests {
    @Test func hasStableURLs() {
        #expect(LaunchRequest.resumeOrNew.url.absoluteString == "dialect://launch/resume-or-new")
        #expect(LaunchRequest.new.url.absoluteString == "dialect://launch/new")
        #expect(LaunchRequest.downloader.url.absoluteString == "dialect://launch/downloader")
    }

    @Test(arguments: LaunchRequest.allCases)
    func roundTripsThroughItsURL(_ request: LaunchRequest) {
        #expect(LaunchRequest(url: request.url) == request)
    }

    @Test(arguments: [
        "dialect://launch/other", "dialect://launch", "dialect://launch/", "dialect://other/new",
        "https://launch/new", "dialect://launch/new/extra", "dialect:launch/new",
    ])
    func rejectsOtherURLs(_ text: String) throws {
        #expect(LaunchRequest(url: try #require(URL(string: text))) == nil)
    }

    /// What its complications show: a title (rectangular), a shorter one
    /// (inline, where a face may cut it short), and the same symbol as the
    /// menu's button for it.
    @Test func presentsItself() {
        #expect(LaunchRequest.resumeOrNew.title.key == "Resume or New")
        #expect(LaunchRequest.new.title.key == "New Session")
        #expect(LaunchRequest.resumeOrNew.inlineTitle.key == "Resume Session")
        #expect(LaunchRequest.new.inlineTitle.key == "New Session")
        #expect(LaunchRequest.resumeOrNew.systemImage == "playpause")
        #expect(LaunchRequest.new.systemImage == "square.and.pencil")
        #expect(LaunchRequest.downloader.title.key == "Downloader")
        #expect(LaunchRequest.downloader.systemImage == "arrow.down.circle")
    }

    @MainActor
    @Test func usesTheMenusSymbols() {
        let menu = Dictionary(
            uniqueKeysWithValues: MainMenu.topRow.map { ($0.route, $0.systemImage) })
        #expect(menu[.newREPL] == LaunchRequest.new.systemImage)
        #expect(menu[.resumeSession] == LaunchRequest.resumeOrNew.systemImage)
    }

    @Test func resumesOnlyWhenThereIsALatestSession() {
        #expect(LaunchRequest.resumeOrNew.route(hasLatestSession: true) == .resumeSession)
        #expect(LaunchRequest.resumeOrNew.route(hasLatestSession: false) == .newREPL)
        #expect(LaunchRequest.new.route(hasLatestSession: true) == .newREPL)
        #expect(LaunchRequest.new.route(hasLatestSession: false) == .newREPL)
        #expect(LaunchRequest.downloader.route(hasLatestSession: true) == .downloader)
    }
}

@MainActor
struct LaunchRouterTests {
    @Test func holdsARequestUntilTheAppTakesIt() {
        let router = LaunchRouter()
        #expect(router.pending == nil)
        router.request(.new)
        #expect(router.pending == .new)
    }

    @Test func opensLaunchLinksAndIgnoresOthers() throws {
        let router = LaunchRouter()
        #expect(!router.open(try #require(URL(string: "https://example.com"))))
        #expect(router.pending == nil)
        #expect(router.open(LaunchRequest.resumeOrNew.url))
        #expect(router.pending == .resumeOrNew)
    }

    /// A launch starts from the menu, so going back from it returns there, not
    /// to wherever the app was before.
    @Test func aLaunchReplacesTheNavigationPath() {
        #expect(LaunchRouter.path(for: .new, hasLatestSession: false) == [.newREPL])
        #expect(LaunchRouter.path(for: .resumeOrNew, hasLatestSession: true) == [.resumeSession])
    }
}

struct FakeSessionsTests {
    /// Until sessions exist, a debug setting stands in for "there is a latest
    /// session".
    @Test func readsThePretendSetting() throws {
        let defaults = try #require(UserDefaults(suiteName: "FakeSessionsTests"))
        defer { defaults.removePersistentDomain(forName: "FakeSessionsTests") }
        #expect(!FakeSessions.hasLatestSession(in: defaults))
        defaults.set(true, forKey: FakeSessions.key)
        #expect(FakeSessions.hasLatestSession(in: defaults))
    }
}

struct DownloadsSnapshotTests {
    /// The fake data the complication shows until there is a downloader.
    @Test func fakeDataIsThreeDownloadsTheFurthestAt62Percent() {
        #expect(DownloadsSnapshot.fake == DownloadsSnapshot(running: 3, furthestProgress: 0.62))
    }

    @Test func readsOutTheCountAndTheFurthestProgress() {
        let snapshot = DownloadsSnapshot(running: 3, furthestProgress: 0.62)
        #expect(snapshot.countText == "3")
        #expect(snapshot.progressText == "62%")
        #expect(snapshot.accessibilityText == "3 downloads, the furthest at 62%")
    }

    @Test func readsOutOneDownload() {
        let snapshot = DownloadsSnapshot(running: 1, furthestProgress: 0.05)
        #expect(snapshot.accessibilityText == "1 download, at 5%")
    }

    /// Nothing running: an empty gauge, not a stale one.
    @Test func showsNothingRunningAsAnEmptyGauge() {
        let idle = DownloadsSnapshot(running: 0, furthestProgress: 0.9)
        #expect(idle.gaugeValue == 0)
        #expect(idle.accessibilityText == "No downloads")
        #expect(DownloadsSnapshot(running: 2, furthestProgress: 1.4).gaugeValue == 1)
    }
}
