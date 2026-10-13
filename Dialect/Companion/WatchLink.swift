import WatchConnectivity
import WatchKit
import os

/// What `WatchLink` needs of the session, so tests can stand in for it.
protocol SettingsSession: AnyObject {
    var isActivated: Bool { get }

    /// Whether the phone can be sent a message now.
    var isReachable: Bool { get }

    /// Whether the system holds anything from the phone not yet delivered.
    var hasContentPending: Bool { get }

    /// Replaces the application context, which the system delivers when it
    /// chooses: at once in a simulator, up to minutes later on a device.
    func send(_ context: [String: Any]) throws

    /// Sends the phone a message at once.
    func sendNow(_ message: [String: Any], failed: @escaping @Sendable (any Error) -> Void)
}

extension WCSession: SettingsSession {
    var isActivated: Bool { activationState == .activated }

    func send(_ context: [String: Any]) throws {
        try updateApplicationContext(context)
    }

    func sendNow(_ message: [String: Any], failed: @escaping @Sendable (any Error) -> Void) {
        sendMessage(message, replyHandler: nil, errorHandler: failed)
    }
}

/// Sends the watch's settings to the phone as a snapshot: in the session's
/// application context, and while the phone is reachable as a message too,
/// which arrives at once and wakes the phone app if need be.
///
/// It sends when the session becomes active, half a second after the settings
/// last changed, and as the app goes to the background. It messages the last
/// snapshot again when the phone becomes reachable.
///
/// It applies the edits in the phone's messages and application context by the
/// rule of `Mirror.applying(_:over:)`, and sends a new snapshot at once.
///
/// Without a paired phone, the session never becomes active and nothing is
/// sent.
@MainActor
final class WatchLink {
    static let shared = WatchLink(
        session: WCSession.default, mirror: .standard, defaults: .standard,
        watchName: WKInterfaceDevice.current().name,
        undoSteps: {
            let stacks = FilesRoot.operations.history.read()
            return stacks.undo.count + stacks.redo.count
        },
        trimHistory: trimFilesHistory)

    private static func trimFilesHistory(to steps: Int) async {
        try? await FilesRoot.operations.trimHistory(to: steps)
    }

    private let session: SettingsSession
    private let mirror: Mirror
    private let defaults: UserDefaults
    private let watchName: String
    private let undoSteps: @MainActor () -> Int
    private let trimHistory: @MainActor (Int) async -> Void
    private let delay: Duration

    /// The publish waiting for the settings to settle.
    private var waiting: Task<Void, Never>?

    /// What the phone was last sent.
    private var sent: SettingsSnapshot?

    /// Trims the undo history to an Undo History from the phone, then publishes
    /// the history's new length.
    private var trimming: Task<Void, Never>?

    /// Whether the edits the session held at activation have been applied.
    private var activationHandled = false

    private var delegate: SessionDelegate?
    private var observer: (any NSObjectProtocol)?

    init(
        session: SettingsSession, mirror: Mirror, defaults: UserDefaults, watchName: String,
        undoSteps: @escaping @MainActor () -> Int,
        trimHistory: @escaping @MainActor (Int) async -> Void, delay: Duration = .milliseconds(500)
    ) {
        self.session = session
        self.mirror = mirror
        self.defaults = defaults
        self.watchName = watchName
        self.undoSteps = undoSteps
        self.trimHistory = trimHistory
        self.delay = delay
    }

    /// Activates the session and follows the settings.
    func start() {
        guard WCSession.isSupported(), delegate == nil else { return }
        followSettings()
        let delegate = SessionDelegate(
            activated: { [weak self] edits in self?.activated(with: edits) },
            reachable: { [weak self] in self?.phoneBecameReachable() },
            received: { [weak self] edits, answering in self?.apply(edits, answering: answering) })
        self.delegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }

    /// Publishes after each change to the settings, once they've settled.
    func followSettings() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    /// Publishes once the settings have been still for the delay, so a burst of
    /// changes, such as a crown-driven slider's, sends one snapshot.
    func settingsChanged() {
        waiting?.cancel()
        waiting = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    /// Applies the edits the session held at activation, then publishes.
    func activated(with edits: PhoneEdits?) {
        activationHandled = true
        if let edits { apply(edits) }
        publish()
    }

    /// Sends the current snapshot, if it differs from the last one sent, and
    /// says whether it did.
    @discardableResult
    func publish() -> Bool {
        waiting?.cancel()
        waiting = nil
        guard session.isActivated else { return false }
        do {
            var snapshot = try mirror.update(with: EffectiveSettings.read(from: defaults))
            snapshot.undoSteps = undoSteps()
            snapshot.watchName = watchName
            guard snapshot != sent else { return false }
            snapshot.sequence = try mirror.nextSequence()
            try session.send(snapshot.propertyList)
            sent = snapshot
            message(snapshot)
            return true
        } catch {
            Self.log.error("Couldn't send the settings: \(error, privacy: .public)")
            return false
        }
    }

    /// Applies what the watch takes of the phone's edits, then publishes at
    /// once. The settings are written before the mirror, so if Dialect stops
    /// between the two, the next snapshot shows a change on the watch to the
    /// edit's value, which then settles the edit.
    func apply(_ edits: PhoneEdits, answering: Bool = false) {
        guard !edits.edits.isEmpty,
            let applied = mirror.applying(edits, over: EffectiveSettings.read(from: defaults))
        else {
            if answering, !edits.edits.isEmpty, !publish(), let sent { message(sent) }
            return
        }
        for (key, value) in applied.values {
            defaults.set(value.propertyList, forKey: key)
        }
        do {
            try mirror.record(applied)
        } catch {
            Self.log.error("Couldn't record the phone's edits: \(error, privacy: .public)")
        }
        publish()
        if applied.values[FileSettings.undoHistoryKey] != nil {
            // As Shorten in the watch's settings does, after any earlier trim, to the latest value.
            trimming = Task { [weak self, trimHistory, defaults, previous = trimming] in
                await previous?.value
                await trimHistory(FileSettings.undoHistory(in: defaults))
                self?.publish()
            }
        }
    }

    /// For a WatchConnectivity background task: waits, ten seconds at most, for
    /// the session to activate and deliver what the system held for it, then
    /// for any history trim, and publishes.
    func waitForDelivery() async {
        for _ in 0..<100 {
            guard !activationHandled || session.hasContentPending else { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        // The delegate passes deliveries to the main actor; let the last ones apply.
        try? await Task.sleep(for: .milliseconds(100))
        await trimming?.value
        publish()
    }

    /// Messages the last snapshot again: a message sent while the phone was out
    /// of reach never arrives, and a context can take minutes.
    func phoneBecameReachable() {
        if let sent { message(sent) }
    }

    private func message(_ snapshot: SettingsSnapshot) {
        guard session.isReachable else { return }
        session.sendNow(snapshot.propertyList) { error in
            Self.log.info("Couldn't message the settings: \(error, privacy: .public)")
        }
    }

    nonisolated private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Dialect", category: "Companion")
}

/// The session's delegate. Its methods are called off the main actor, and pass
/// what they get to the main actor in the order it arrives.
private final class SessionDelegate: NSObject, WCSessionDelegate {
    /// Called with the phone's edits from the context the session holds.
    private let activated: @MainActor @Sendable (PhoneEdits?) -> Void
    private let reachable: @MainActor @Sendable () -> Void
    /// Called with the edits and whether they came by message.
    private let received: @MainActor @Sendable (PhoneEdits, Bool) -> Void

    init(
        activated: @escaping @MainActor @Sendable (PhoneEdits?) -> Void,
        reachable: @escaping @MainActor @Sendable () -> Void,
        received: @escaping @MainActor @Sendable (PhoneEdits, Bool) -> Void
    ) {
        self.activated = activated
        self.reachable = reachable
        self.received = received
    }

    private func onMain(_ action: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { action() }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        onMain { [reachable] in reachable() }
    }

    func session(
        _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard state == .activated else { return }
        let edits = PhoneEdits(propertyList: session.receivedApplicationContext)
        onMain { [activated] in activated(edits) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let edits = PhoneEdits(propertyList: context) else { return }
        onMain { [received] in received(edits, false) }
    }

    /// The phone's edits, sent at once while Dialect is open.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let edits = PhoneEdits(propertyList: message) else { return }
        onMain { [received] in received(edits, true) }
    }
}
