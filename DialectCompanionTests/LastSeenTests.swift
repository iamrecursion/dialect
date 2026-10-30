import Foundation
import Testing

@testable import DialectCompanion

struct LastSeenTests {
    private let english = Locale(identifier: "en_US")

    /// Elapsed seconds and the step they fall in.
    private static let steps: [(Double, Double)] = [
        (0, 0), (59, 0), (60, 60), (299, 240), (300, 300), (599, 300), (600, 600), (1199, 600),
        (1200, 1200), (1799, 1200), (1800, 1800), (3599, 1800), (3600, 3600), (7199, 3600),
        (86399, 82800), (86400, 86400), (3 * 86400 + 5, 3 * 86400), (13 * 86400, 7 * 86400),
        (14 * 86400, 14 * 86400),
    ]

    @Test(arguments: steps)
    func stepsDown(elapsed: Double, step: Double) {
        #expect(LastSeen.step(for: elapsed) == step)
    }

    @Test func readsAsAPhrase() {
        #expect(LastSeen.phrase(for: 30, locale: english) == "seconds ago")
        #expect(LastSeen.phrase(for: 61, locale: english) == "1 minute ago")
        #expect(LastSeen.phrase(for: 7 * 60, locale: english) == "5 minutes ago")
        #expect(LastSeen.phrase(for: 45 * 60, locale: english) == "30 minutes ago")
        #expect(LastSeen.phrase(for: 2.5 * 3600, locale: english) == "2 hours ago")
        #expect(LastSeen.phrase(for: 3 * 86400, locale: english) == "3 days ago")
        #expect(LastSeen.phrase(for: 15 * 86400, locale: english) == "2 weeks ago")
    }

    @Test func changesExactlyWhenThePhraseDoes() {
        let seen = Date(timeIntervalSinceReferenceDate: 0)
        let changes = LastSeen.changes(after: seen)
        #expect(changes == changes.sorted())
        for change in changes {
            let elapsed = change.timeIntervalSince(seen)
            #expect(
                LastSeen.phrase(for: elapsed - 1, locale: english)
                    != LastSeen.phrase(for: elapsed, locale: english))
        }
    }

    @Test func onlyTheCacheHasASubtitle() {
        let seen = Date(timeIntervalSinceReferenceDate: 0)
        let now = seen.addingTimeInterval(12 * 60)
        #expect(
            BrowsingState.cached(seen).subtitle(of: .folder, now: now).hasPrefix(
                "Folder last seen 10 minutes"))
        #expect(BrowsingState.live.subtitle(of: .folder, now: now).isEmpty)
    }
}
