import Foundation

/// A way into Dialect from outside: a shortcut action, a complication or the
/// Action Button.
enum LaunchRequest: String, Hashable, Sendable, CaseIterable {
    /// The latest session if there is one, else a new one.
    case resumeOrNew = "resume-or-new"

    /// A new session, whatever else there is.
    case new

    /// The downloader: what the downloads complication opens.
    case downloader

    /// Its name in full, where there is room (a rectangular complication).
    var title: LocalizedStringResource {
        switch self {
        case .resumeOrNew: return "Resume or New"
        case .new: return "New Session"
        case .downloader: return "Downloader"
        }
    }

    /// Its name on one line, where a face may cut it short (an inline
    /// complication).
    var inlineTitle: LocalizedStringResource {
        switch self {
        case .resumeOrNew: return "Resume Session"
        case .new: return "New Session"
        case .downloader: return "Downloader"
        }
    }

    /// The same symbol as the menu's button for it.
    var systemImage: String {
        switch self {
        case .resumeOrNew: return "playpause"
        case .new: return "square.and.pencil"
        case .downloader: return "arrow.down.circle"
        }
    }

    /// How far to nudge its symbol up (negative) or down, in points at
    /// `.title3`, where the eye finds its centre somewhere other than its
    /// bounding box does: `square.and.pencil`'s pencil tip sticks up above its
    /// square.
    var opticalOffset: Double {
        return self == .new ? -1.5 : 0
    }

    static let scheme = "dialect"
    private static let host = "launch"

    /// `dialect://launch/<request>`: what a complication opens.
    var url: URL {
        return URL(string: "\(Self.scheme)://\(Self.host)/\(rawValue)")!
    }

    /// The request a `dialect://launch/…` link names; `nil` for any other URL.
    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == Self.host else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        guard path.count == 1, let request = LaunchRequest(rawValue: path[0]) else { return nil }
        self = request
    }
}
