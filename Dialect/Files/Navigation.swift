import SwiftUI

/// The app's navigation path, shared through the environment so any screen can
/// push, pop and replace.
///
/// More never stays in the history: an item on a More screen that opens a
/// screen calls `replaceTop(with:)`, so backing out of that screen lands on the
/// folder; one that only acts calls `pop()`.
@MainActor @Observable
final class Navigation {
    var path: [Route]

    init(path: [Route] = []) {
        self.path = path
    }

    func push(_ route: Route) {
        path.append(route)
    }

    /// Goes back one screen, also skipping a replaced screen that hasn't been
    /// dropped yet.
    func pop() {
        if let pending = pendingReplace, Array(path.suffix(2)) == [pending.replaced, pending.route]
        {
            pendingDrop?.cancel()
            pendingReplace = nil
            path.removeLast(2)
            return
        }
        if !path.isEmpty { path.removeLast() }
    }

    /// Goes back to the last `route` on the path; does nothing when it isn't
    /// there.
    func pop(to route: Route) {
        guard let index = path.lastIndex(of: route) else { return }
        truncate(to: index + 1)
    }

    /// Leaves an item that's gone: drops the first relevant screen, and every
    /// screen above that, so nothing is left showing it.
    func leave(_ item: FilePath) {
        guard let index = path.firstIndex(where: { $0.filePath?.isWithin(item) == true })
        else { return }
        truncate(to: index)
    }

    /// Keeps the first `count` screens.
    private func truncate(to count: Int) {
        guard count < path.count else { return }
        path.removeSubrange(count...)
        if let pending = pendingReplace, !path.contains(pending.route) {
            pendingDrop?.cancel()
            pendingReplace = nil
        }
    }

    /// How long a replace waits for its push to finish animating before it
    /// drops the screen it replaced.
    @ObservationIgnored var replaceDelay: Duration = .milliseconds(500)

    /// The drop a replace has scheduled, for tests to await.
    @ObservationIgnored private(set) var pendingDrop: Task<Void, Never>?

    /// The replace whose drop hasn't happened yet.
    @ObservationIgnored private var pendingReplace: (replaced: Route, route: Route)?

    /// Replaces the top screen as far as Back is concerned, while animating as
    /// an ordinary push: the new screen is pushed, then the one it replaces is
    /// dropped from under it once the push has settled.
    func replaceTop(with route: Route) {
        guard let replaced = path.last else {
            path.append(route)
            return
        }
        path.append(route)
        pendingDrop?.cancel()
        pendingReplace = (replaced, route)
        let delay = replaceDelay
        pendingDrop = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if self.pendingReplace?.replaced == replaced && self.pendingReplace?.route == route {
                self.pendingReplace = nil
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                _ = self.path.drop(replaced, under: route)
            }
        }
    }
}

extension Array where Element == Route {
    /// Removes `replaced` from just under `route`, as screens may have been
    /// pushed over `route` since; does nothing when the pair is gone.
    mutating func drop(_ replaced: Route, under route: Route) -> Bool {
        guard
            let index = indices.dropLast().last(where: {
                self[$0] == replaced && self[$0 + 1] == route
            })
        else { return false }
        remove(at: index)
        return true
    }
}
