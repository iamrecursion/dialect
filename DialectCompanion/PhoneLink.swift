import Observation
import WatchConnectivity
import os

/// What the phone knows about the watch, kept up to date from the session, and
/// the phone's edits to the watch's settings. The session keeps both apps' last
/// application contexts.
@MainActor @Observable
final class PhoneLink {
    /// `nil` until the session is active.
    private(set) var facts: LinkFacts?

    /// The phone's edits the watch hasn't handled.
    private(set) var edits = PhoneEdits.empty

    /// Settings whose edits the watch dropped for another value, until the user
    /// goes back to Settings or edits them again.
    private(set) var changedOnWatch: Set<String> = []

    /// Where Files keeps what it remembers of this watch, inside
    /// `WCSession.watchDirectoryURL`, which is `nil` until the session is
    /// active and changes with the watch.
    private(set) var watchDirectory: URL?

    @ObservationIgnored private var delegate: SessionDelegate?

    /// The send waiting for the edits to settle.
    @ObservationIgnored private var sending: Task<Void, Never>?

    init(facts: LinkFacts? = nil, watchDirectory: URL? = nil) {
        self.facts = facts
        self.watchDirectory = watchDirectory
    }

    var status: LinkStatus? { facts.map(LinkStatus.init) }

    /// The watch's settings, when the status shows them.
    var snapshot: SettingsSnapshot? {
        guard status?.showsSettings == true else { return nil }
        return facts?.snapshot.snapshot
    }

    /// The watch's name, or "Apple Watch" if it hasn't said.
    var watchName: String {
        return facts?.snapshot.snapshot?.watchName ?? String(localized: "Apple Watch")
    }

    /// A setting as the phone shows it: the waiting edit's value, if there is
    /// one, otherwise the watch's.
    func value(_ key: String) -> SettingValue? {
        guard let snapshot else { return nil }
        return edits.value(key) ?? snapshot.value(key)
    }

    func isWaiting(_ key: String) -> Bool {
        return edits.edits[key] != nil
    }

    func isChangedOnWatch(_ key: String) -> Bool {
        return changedOnWatch.contains(key)
    }

    /// Edits a setting for the watch to apply.
    func edit(_ key: String, to value: SettingValue) {
        guard let snapshot, MirroredSettings.accepts(value, for: key) else { return }
        changedOnWatch.remove(key)

        let next = edits.editing(key, to: value, against: snapshot)
        guard next != edits else { return }
        edits = next

        sending?.cancel()
        sending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.send()
        }
    }

    /// Clears every "Changed on the Watch", as the user goes back to Settings.
    func forgetChangedOnWatch() {
        changedOnWatch = []
    }

    /// Sends a waiting send at once, as the app leaves the foreground.
    func flush() {
        guard sending != nil else { return }
        send()
    }

    /// Puts the edits in the phone's context and, while the watch is reachable,
    /// messages them for the watch to apply at once.
    private func send(messaging: Bool = true) {
        sending?.cancel()
        sending = nil

        guard delegate != nil else { return }
        let session = WCSession.default

        guard session.activationState == .activated else { return }
        let list = edits.propertyList
        do {
            try session.updateApplicationContext(list)
        } catch {
            Self.log.error("Couldn't keep the edits: \(error, privacy: .public)")
        }

        guard messaging, session.isReachable, !edits.edits.isEmpty else { return }
        Self.message(list, on: session)
    }

    /// Off the main actor, as WatchConnectivity calls the error handler on its
    /// queue.
    nonisolated private static func message(_ list: [String: Any], on session: WCSession) {
        session.sendMessage(list, replyHandler: nil) { error in
            log.info("Couldn't message the edits: \(error, privacy: .public)")
        }
    }

    /// Takes the session's facts, and the snapshot that came with them if it's
    /// newer than the one held, then settles the edits the watch has handled
    /// and sends the rest again if the watch just became reachable.
    func update(
        _ session: LinkFacts, snapshot: ReceivedSnapshot?, edits stored: PhoneEdits?,
        watchDirectory: URL?
    ) {
        let wasReachable = facts?.isReachable ?? false
        self.watchDirectory = watchDirectory
        var facts = session
        facts.snapshot = ReceivedSnapshot.latest(snapshot, over: self.facts?.snapshot ?? .none)
        self.facts = facts

        // A send still waiting holds edits newer than the stored context's.
        if let stored, sending == nil { edits = stored }
        if let snapshot = facts.snapshot.snapshot, !edits.edits.isEmpty {
            let (next, changed) = edits.resolved(by: snapshot)
            changedOnWatch.formUnion(changed)
            if next != edits {
                edits = next
                // A waiting send sends these; otherwise the context drops what's handled.
                if sending == nil { send(messaging: false) }
            }
        }

        // A message sent while the watch was out of reach never arrived.
        if facts.isReachable, !wasReachable, !edits.edits.isEmpty, sending == nil { send() }
    }

    /// Activates the session. Off the main actor, `filesAnswers` hears the
    /// answers to requests from Files that came by user info, and
    /// `reachability` whether the watch is reachable, each time the session
    /// says.
    func start(
        filesAnswers: @escaping @Sendable (FilesUserInfo) -> Void,
        reachability: @escaping @Sendable (Bool) -> Void
    ) {
        guard WCSession.isSupported(), delegate == nil else { return }
        let delegate = SessionDelegate(filesAnswers: filesAnswers, reachability: reachability) {
            [weak self] facts, snapshot, edits, directory in
            self?.update(facts, snapshot: snapshot, edits: edits, watchDirectory: directory)
        }
        self.delegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }

    nonisolated private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DialectCompanion", category: "Companion")
}

/// The session's delegate. Its methods are called off the main actor, and pass
/// the session's facts, with any snapshot or stored edits, to the main actor in
/// the order they arrive.
private final class SessionDelegate: NSObject, WCSessionDelegate {
    /// With the phone's edits from its context, at activation.
    private let update:
        @MainActor @Sendable (LinkFacts, ReceivedSnapshot?, PhoneEdits?, URL?) -> Void
    private let filesAnswers: @Sendable (FilesUserInfo) -> Void
    private let reachability: @Sendable (Bool) -> Void

    init(
        filesAnswers: @escaping @Sendable (FilesUserInfo) -> Void,
        reachability: @escaping @Sendable (Bool) -> Void,
        update:
            @escaping @MainActor @Sendable (LinkFacts, ReceivedSnapshot?, PhoneEdits?, URL?) ->
            Void
    ) {
        self.filesAnswers = filesAnswers
        self.reachability = reachability
        self.update = update
    }

    private func report(
        _ session: WCSession, snapshot: ReceivedSnapshot? = nil, edits: PhoneEdits? = nil
    ) {
        let facts: LinkFacts
        if session.activationState == .activated {
            facts = LinkFacts(
                isPaired: session.isPaired, isWatchAppInstalled: session.isWatchAppInstalled,
                isReachable: session.isReachable, snapshot: .none)
        } else {
            // Shown as unpaired: without an active session, there's no watch to reach.
            facts = LinkFacts(
                isPaired: false, isWatchAppInstalled: false, isReachable: false, snapshot: .none)
        }
        let directory =
            session.activationState == .activated
            ? session.watchDirectoryURL?.appending(path: "Files", directoryHint: .isDirectory)
            : nil
        reachability(facts.isReachable)
        DispatchQueue.main.async { [update] in
            MainActor.assumeIsolated { update(facts, snapshot, edits, directory) }
        }
    }

    func session(
        _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
        error: (any Error)?
    ) {
        report(
            session, snapshot: ReceivedSnapshot(propertyList: session.receivedApplicationContext),
            edits: PhoneEdits(propertyList: session.applicationContext) ?? .empty)
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        report(session, snapshot: ReceivedSnapshot(propertyList: context))
    }

    /// The watch's snapshot, sent at once while the phone is reachable.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        report(session, snapshot: ReceivedSnapshot(message: message))
    }

    /// An answer from Files, for a request sent while the watch wasn't
    /// reachable.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let answer = FilesUserInfo(answer: userInfo) { filesAnswers(answer) }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        report(session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        report(session)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched to another watch.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
