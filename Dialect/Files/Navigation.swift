import SwiftUI

/// The app's navigation path, shared through the environment so any screen can
/// push, pop and replace.
///
/// More never stays in the history: an item on a More screen that opens a
/// screen calls `replaceTop(with:)`, so backing out of that screen lands on the
/// folder; one that only acts calls `pop()`.
@MainActor @Observable
final class Navigation {
    var path: [Route] {
        didSet {
            // A reveal is its folder's while that's on top.
            if let revealing, path.last != Self.folderOnTop(for: revealing) {
                self.revealing = nil
            }
            if let hiddenShown, !path.contains(hiddenShown) {
                self.hiddenShown = nil
            }
        }
    }

    /// The folder Show in Files brought a hidden item into view in, which lists
    /// hidden items while it's on the path, whatever Show Hidden says.
    private var hiddenShown: Route?

    /// The item Show in Files is bringing into view. It lasts until its folder
    /// has finished, or is no longer on top, as the folder's screen may be
    /// rebuilt meanwhile and start again.
    private(set) var revealing: FilePath?

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

    /// Goes back to the main menu.
    func popToRoot() {
        truncate(to: 0)
    }

    /// Leaves an item that's gone: drops the first relevant screen, and every
    /// screen above that, so nothing is left showing it.
    func leave(_ item: FilePath) {
        guard let index = path.firstIndex(where: { $0.filePath?.isWithin(item) == true })
        else { return }
        truncate(to: index)
    }

    /// Opens the item's folder as if browsed to from the main menu, and has it
    /// bring the item into view, listing hidden items there if it's hidden. The
    /// folders are pushed, so it animates as a push, then what was under them
    /// is dropped once the push has settled. Only then is the item revealed, as
    /// the drop rebuilds the folder's screen.
    func show(_ item: FilePath) {
        guard let folder = item.parent else { return }
        let under = path
        path.append(contentsOf: Self.folders(to: folder))
        revealing = nil
        if item.name?.hasPrefix(".") == true { hiddenShown = Route.folderRoute(for: folder) }
        pendingShow?.cancel()
        let delay = replaceDelay
        pendingShow = Task { [weak self] in
            try? await Task.sleep(for: delay)
            // Unless Back has gone below Files meanwhile.
            guard !Task.isCancelled, let self, self.path.starts(with: under + [.files]) else {
                return
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.path.removeFirst(under.count)
            }
            if self.path.last == Self.folderOnTop(for: item) { self.revealing = item }
        }
    }

    /// The item to bring into view in `folder`, if any.
    func reveal(in folder: FilePath) -> FilePath? {
        guard let revealing, revealing.parent == folder else { return nil }
        return revealing
    }

    func endReveal() {
        revealing = nil
    }

    /// Whether `folder` lists hidden items for Show in Files, though Show
    /// Hidden is off.
    func showsHidden(in folder: FilePath) -> Bool {
        return hiddenShown == Route.folderRoute(for: folder)
    }

    /// The routes from Files down to `folder`, as browsing leaves them.
    static func folders(to folder: FilePath) -> [Route] {
        return [.files]
            + folder.components.indices.map {
                .folder(FilePath(components: Array(folder.components[...$0])))
            }
    }

    private static func folderOnTop(for item: FilePath) -> Route {
        return Route.folderRoute(for: item.parent ?? .root)
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

    /// The drop Show in Files has scheduled, apart from a replace's, so a
    /// replace made meanwhile doesn't cancel it.
    @ObservationIgnored private(set) var pendingShow: Task<Void, Never>?

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
