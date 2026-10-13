import Foundation

/// What the phone knows of the watch: the session's facts and the last
/// snapshot.
struct LinkFacts: Equatable, Sendable {
    var isPaired: Bool
    var isWatchAppInstalled: Bool

    /// Whether Dialect is open on the watch.
    var isReachable: Bool
    var snapshot: ReceivedSnapshot
}

/// The watch's last snapshot, as the phone reads it.
enum ReceivedSnapshot: Equatable, Sendable {
    /// The watch hasn't sent one.
    case none
    case readable(SettingsSnapshot)

    /// A snapshot in a format this app can't read; `newer` if the watch has the
    /// newer Dialect.
    case otherFormat(newer: Bool)

    init(propertyList list: [String: Any]) {
        if list.isEmpty {
            self = .none
        } else if let snapshot = SettingsSnapshot(propertyList: list) {
            self = .readable(snapshot)
        } else if let format = SettingsSnapshot.format(of: list),
            format != SettingsSnapshot.format
        {
            self = .otherFormat(newer: format > SettingsSnapshot.format)
        } else {
            // Damaged: the watch sends a whole snapshot with its next change.
            self = .none
        }
    }

    /// A message's snapshot; `nil` for a message that isn't one.
    init?(message: [String: Any]) {
        guard SettingsSnapshot.format(of: message) != nil else { return nil }
        self.init(propertyList: message)
    }

    var snapshot: SettingsSnapshot? {
        guard case .readable(let snapshot) = self else { return nil }
        return snapshot
    }

    /// `incoming`, unless nothing came or what came is older than `held`.
    static func latest(_ incoming: ReceivedSnapshot?, over held: ReceivedSnapshot)
        -> ReceivedSnapshot
    {
        guard let incoming else { return held }
        if let new = incoming.snapshot, let old = held.snapshot, new.isOlder(than: old) {
            return held
        }
        return incoming
    }
}

/// The watch's connection, as the Watch tab shows it.
enum LinkStatus: Equatable, Sendable {
    case unpaired
    case notInstalled

    /// Dialect hasn't run on the watch since it was installed.
    case noSnapshot

    /// Dialect on the watch is newer (`watchIsNewer`) or older than on the
    /// phone.
    case otherFormat(watchIsNewer: Bool)

    /// Dialect is open on the watch.
    case connected

    /// The watch is out of reach, or Dialect isn't open on it.
    case away

    /// The first that applies, in order.
    init(_ facts: LinkFacts) {
        if !facts.isPaired {
            self = .unpaired
        } else if !facts.isWatchAppInstalled {
            self = .notInstalled
        } else {
            switch facts.snapshot {
            case .none: self = .noSnapshot
            case .otherFormat(let newer): self = .otherFormat(watchIsNewer: newer)
            case .readable: self = facts.isReachable ? .connected : .away
            }
        }
    }

    /// Whether Settings shows the watch's settings.
    var showsSettings: Bool {
        switch self {
        case .connected, .away: return true
        case .unpaired, .notInstalled, .noSnapshot, .otherFormat: return false
        }
    }
}
