import Testing

@testable import Dialect

/// The watch's connection, from what the phone knows of it.
struct LinkStatusTests {
    private static let snapshot = ReceivedSnapshot.readable(
        SettingsSnapshot(epoch: "E", settings: [:]))

    private func status(
        paired: Bool = true, installed: Bool = true, reachable: Bool = true,
        snapshot: ReceivedSnapshot = snapshot
    ) -> LinkStatus {
        return LinkStatus(
            LinkFacts(
                isPaired: paired, isWatchAppInstalled: installed, isReachable: reachable,
                snapshot: snapshot))
    }

    @Test func connectedWhenReachable() {
        #expect(status() == .connected)
        #expect(status(reachable: false) == .away)
    }

    /// A snapshot left from before doesn't outrank the watch being gone.
    @Test func unpairedComesFirst() {
        #expect(status(paired: false) == .unpaired)
        #expect(status(paired: false, installed: false) == .unpaired)
    }

    @Test func thenTheWatchApp() {
        #expect(status(installed: false) == .notInstalled)
        #expect(status(installed: false, snapshot: .none) == .notInstalled)
    }

    @Test func thenTheSnapshot() {
        #expect(status(snapshot: .none) == .noSnapshot)
        #expect(status(reachable: false, snapshot: .none) == .noSnapshot)
        #expect(status(snapshot: .otherFormat(newer: true)) == .otherFormat(watchIsNewer: true))
        #expect(
            status(reachable: false, snapshot: .otherFormat(newer: false))
                == .otherFormat(watchIsNewer: false))
    }

    @Test func showsSettingsOnlyWithASnapshotToShow() {
        #expect(LinkStatus.connected.showsSettings)
        #expect(LinkStatus.away.showsSettings)
        for status in [
            LinkStatus.unpaired, .notInstalled, .noSnapshot, .otherFormat(watchIsNewer: true),
        ] {
            #expect(!status.showsSettings)
        }
    }
}
