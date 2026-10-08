import Foundation
import Observation

extension LaunchRequest {
    /// The screen the request lands on.
    func route(hasLatestSession: Bool) -> Route {
        switch self {
        case .resumeOrNew: return hasLatestSession ? .resumeSession : .newREPL
        case .new: return .newREPL
        case .downloader: return .downloader
        }
    }
}

/// Carries launch requests from where they arrive (shortcut actions,
/// complication links) to the app's navigation.
@MainActor
@Observable
final class LaunchRouter {
    static let shared = LaunchRouter()

    /// A request the app has not acted on yet.
    private(set) var pending: LaunchRequest?

    func request(_ request: LaunchRequest) {
        pending = request
    }

    /// Follows a `dialect://launch/…` link, such as a complication's; returns
    /// whether it was one.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let request = LaunchRequest(url: url) else { return false }
        self.request(request)
        return true
    }

    /// The pending request, which is then gone.
    func take() -> LaunchRequest? {
        defer { pending = nil }
        return pending
    }

    /// The navigation path a launch leaves: its screen alone, over the menu, so
    /// going back returns to the menu.
    static func path(for request: LaunchRequest, hasLatestSession: Bool) -> [Route] {
        return [request.route(hasLatestSession: hasLatestSession)]
    }
}

/// Stands in for the session store until sessions exist: whether there is a
/// latest session to resume is a debug launch argument.
enum FakeSessions {
    static let key = "pretendSessionExists"

    static func hasLatestSession(in defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
            return defaults.bool(forKey: key)
        #else
            return false
        #endif
    }
}
