import Foundation
import Testing

@testable import Dialect

/// When the watch sends its settings.
@MainActor
struct WatchLinkTests {
    /// Stands in for the session, keeping what's sent.
    private final class Session: SettingsSession {
        var isActivated = true
        var isReachable = false
        var hasContentPending = false
        var fails = false
        var sent: [[String: Any]] = []
        var messages: [[String: Any]] = []

        func send(_ context: [String: Any]) throws {
            if fails { throw CocoaError(.featureUnsupported) }
            sent.append(context)
        }

        func sendNow(
            _ message: [String: Any], failed: @escaping @Sendable (any Error) -> Void
        ) {
            messages.append(message)
        }
    }

    private let root: TemporaryRoot
    private let store = TestDefaults()
    private var defaults: UserDefaults { store.defaults }
    private let session = Session()
    private let link: WatchLink
    private let trims = Trims()

    /// The undo history's length, and the lengths it was trimmed to.
    @MainActor private final class Trims {
        var steps = 4
        var lengths: [Int] = []
    }

    /// Short enough for quick tests, and long next to the gaps between changes.
    private static let delay = Duration.milliseconds(300)

    init() throws {
        root = try TemporaryRoot()
        let trims = trims
        link = WatchLink(
            session: session, mirror: Mirror(url: root.url.appending(path: "Mirror.json")),
            defaults: store.defaults, watchName: "Eir", undoSteps: { trims.steps },
            trimHistory: { steps in
                trims.lengths.append(steps)
                trims.steps = min(trims.steps, steps)
            }, delay: Self.delay)
    }

    private func sentSnapshots() -> [SettingsSnapshot?] {
        return session.sent.map(SettingsSnapshot.init(propertyList:))
    }

    @Test func sendsTheSnapshot() throws {
        defaults.set(true, forKey: FileSettings.showHiddenKey)
        link.publish()
        let snapshot = try #require(sentSnapshots().first ?? nil)
        #expect(snapshot.value(FileSettings.showHiddenKey) == .bool(true))
        #expect(snapshot.undoSteps == 4)
        #expect(snapshot.watchName == "Eir")
    }

    /// Several changes within the delay send one snapshot, after it.
    @Test func waitsForTheSettingsToSettle() async throws {
        for steps in [20, 50, 100, 50] {
            defaults.set(steps, forKey: FileSettings.undoHistoryKey)
            link.settingsChanged()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.sent.isEmpty)
        try await Task.sleep(for: Self.delay * 3)
        #expect(session.sent.count == 1)
        #expect(sentSnapshots().first??.value(FileSettings.undoHistoryKey) == .int(50))
    }

    @Test func sendsNothingUnchanged() {
        link.publish()
        link.publish()
        #expect(session.sent.count == 1)
        defaults.set(false, forKey: FileSettings.foldersFirstKey)
        link.publish()
        #expect(session.sent.count == 2)
    }

    @Test func sendsNothingBeforeTheSessionIsActive() {
        session.isActivated = false
        link.publish()
        #expect(session.sent.isEmpty)
    }

    /// A change to the settings publishes, once they've settled.
    @Test func followsTheSettings() async throws {
        link.followSettings()
        defaults.set(true, forKey: FileSettings.showDetailsKey)
        try await Task.sleep(for: Self.delay * 3)
        #expect(session.sent.count == 1)
        #expect(sentSnapshots().first??.value(FileSettings.showDetailsKey) == .bool(true))
    }

    /// A context can take minutes to reach the phone, so a reachable phone is
    /// messaged too.
    @Test func messagesAReachablePhone() throws {
        link.publish()
        #expect(session.messages.isEmpty)
        session.isReachable = true
        defaults.set(true, forKey: FileSettings.showHiddenKey)
        link.publish()
        #expect(session.sent.count == 2)
        let message = try #require(session.messages.first)
        #expect(
            SettingsSnapshot(propertyList: message)?.value(FileSettings.showHiddenKey)
                == .bool(true))
    }

    @Test func numbersEachSnapshot() {
        link.publish()
        defaults.set(true, forKey: FileSettings.showHiddenKey)
        link.publish()
        #expect(sentSnapshots().map { $0?.sequence } == [1, 2])
    }

    /// A message sent while the phone was out of reach never arrives, so the
    /// last snapshot is sent again when it's back.
    @Test func messagesAgainWhenThePhoneIsBack() throws {
        link.publish()
        #expect(session.messages.isEmpty)
        session.isReachable = true
        link.phoneBecameReachable()
        let message = try #require(session.messages.first)
        #expect(SettingsSnapshot(propertyList: message) == sentSnapshots().first ?? nil)
    }

    /// A snapshot that couldn't be sent is sent with the next publish.
    @Test func triesAgainAfterAFailedSend() {
        session.isReachable = true
        session.fails = true
        link.publish()
        #expect(session.messages.isEmpty)
        session.fails = false
        link.publish()
        #expect(session.sent.count == 1)
        #expect(session.messages.count == 1)
    }

    // MARK: The phone's edits

    /// An edit against the last snapshot sent.
    private func edit(_ key: String, to value: SettingValue) throws -> PhoneEdits {
        let snapshot = try #require(sentSnapshots().last ?? nil)
        let base = try #require(snapshot.settings[key]).version
        return PhoneEdits(
            epoch: snapshot.epoch, edits: [key: .init(value: value, base: base, revision: 1)])
    }

    /// The phone hears at once, by message while it's reachable.
    @Test func appliesAnEditAndPublishesAtOnce() throws {
        link.publish()
        session.isReachable = true
        link.apply(try edit(FileSettings.showHiddenKey, to: .bool(true)))
        #expect(defaults.object(forKey: FileSettings.showHiddenKey) as? Bool == true)
        #expect(session.sent.count == 2)
        let setting = try #require(sentSnapshots().last??.settings[FileSettings.showHiddenKey])
        #expect(setting.value == .bool(true))
        #expect(setting.edit == EditStamp(base: 1, revision: 1))
        #expect(session.messages.count == 1)
    }

    @Test func sendsNothingWhenNothingApplies() throws {
        link.publish()
        var stale = try edit(FileSettings.showHiddenKey, to: .bool(true))
        stale.epoch = "OLD"
        link.apply(stale)
        #expect(defaults.object(forKey: FileSettings.showHiddenKey) == nil)
        #expect(session.sent.count == 1)
    }

    /// As Shorten in the watch's settings does, then sends the history's new
    /// length.
    @Test func trimsTheHistoryForAShorterUndoHistory() async throws {
        trims.steps = 30
        defaults.set(100, forKey: FileSettings.undoHistoryKey)
        link.publish()
        link.apply(try edit(FileSettings.undoHistoryKey, to: .int(20)))
        #expect(defaults.integer(forKey: FileSettings.undoHistoryKey) == 20)
        try await Task.sleep(for: .milliseconds(50))
        #expect(trims.lengths == [20])
        #expect(sentSnapshots().last??.undoSteps == 20)
    }

    /// A later revision's trim follows the earlier one's, to the latest value.
    @Test func trimsToTheLatestUndoHistory() async throws {
        defaults.set(100, forKey: FileSettings.undoHistoryKey)
        link.publish()
        var edits = try edit(FileSettings.undoHistoryKey, to: .int(20))
        link.apply(edits)
        edits.edits[FileSettings.undoHistoryKey]?.value = .int(50)
        edits.edits[FileSettings.undoHistoryKey]?.revision = 2
        link.apply(edits)
        try await Task.sleep(for: .milliseconds(50))
        #expect(trims.lengths == [50, 50])
    }

    /// In the background, the edits the session held at activation apply before
    /// the task returns.
    @Test func waitsForTheActivationsEdits() async throws {
        link.publish()
        let edits = try edit(FileSettings.showHiddenKey, to: .bool(true))
        let waiting = Task { await link.waitForDelivery() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(defaults.object(forKey: FileSettings.showHiddenKey) == nil)
        link.activated(with: edits)
        await waiting.value
        #expect(defaults.object(forKey: FileSettings.showHiddenKey) as? Bool == true)
        #expect(session.sent.count == 2)
    }

    /// Settings changed by an edit send one snapshot; the delayed publish that
    /// follows finds nothing new.
    @Test func publishesOnceAfterApplying() async throws {
        link.publish()
        link.followSettings()
        link.apply(try edit(FileSettings.showHiddenKey, to: .bool(true)))
        try await Task.sleep(for: Self.delay * 3)
        #expect(session.sent.count == 2)
    }

    /// An edit made against an old snapshot is dropped; the phone gets the
    /// newest, which settles it.
    @Test func answersAMessageItDropsWithTheSnapshot() throws {
        link.publish()
        session.isReachable = true
        var stale = try edit(FileSettings.showHiddenKey, to: .bool(true))
        stale.edits[FileSettings.showHiddenKey]?.base = 0
        link.apply(stale, answering: true)
        #expect(session.sent.count == 1)
        #expect(session.messages.count == 1)
        // The same edit from the context gets no answer; only messages are answered.
        link.apply(stale)
        #expect(session.messages.count == 1)
    }
}
