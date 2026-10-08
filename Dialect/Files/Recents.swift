import Foundation

/// The files and sessions opened last, newest first, for Recents, with up to
/// three pinned at the top.
///
/// Reading never writes, so screens can read it off the actor.
struct Recents: Sendable {
    /// How many unpinned items it keeps: as many as the longest Show Last, so
    /// lengthening Show Last brings older ones back.
    static let capacity = 20

    static let pinLimit = 3

    /// The file it's kept in, written whole each time, so a reader never sees
    /// half of it.
    let url: URL

    /// What it holds, gone or not.
    struct Held: Equatable, Sendable {
        /// Newest first, pinned ones included, so pins keep their own order.
        var paths: [FilePath] = []
        var pinned: [FilePath] = []

        /// Keeps every pin and the newest `capacity` others.
        func trimmed() -> Held {
            var others = 0
            let kept = paths.filter { path in
                if pinned.contains(path) { return true }
                others += 1
                return others <= Recents.capacity
            }
            return Held(paths: kept, pinned: pinned.filter(kept.contains))
        }

        /// Changed as Files changed the items, a pin with its item.
        func changing(_ change: ([FilePath]) -> [FilePath]) -> Held {
            return Held(paths: change(paths), pinned: change(pinned))
        }
    }

    /// What a screen shows.
    struct Listing: Sendable {
        var pinned: [FileItem] = []
        var recent: [FileItem] = []

        /// Pins first.
        var all: [FileItem] { pinned + recent }
    }

    private struct Record: Codable {
        var format = 1
        var items: [FilePath]

        /// Missing from files written before pins.
        var pinned: [FilePath]?
    }

    /// Nothing when its file can't be read.
    func held() -> Held {
        guard let data = try? Data(contentsOf: url),
            let record = try? JSONDecoder().decode(Record.self, from: data)
        else { return Held() }
        return Held(paths: record.items, pinned: record.pinned ?? [])
    }

    func paths() -> [FilePath] {
        return held().paths
    }

    func write(_ held: Held) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let record = Record(items: held.paths, pinned: held.pinned)
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }

    func write(_ paths: [FilePath]) throws {
        try write(Held(paths: paths))
    }

    /// The pins still there, newest first, then the first `limit` other items
    /// still there. Other hidden items, and anything else in a hidden folder,
    /// are left out unless `showHidden`; a pin is always listed, so every pin
    /// counting toward the limit can be seen.
    func listing(root: URL, textExtensions: Set<String>, showHidden: Bool, limit: Int)
        -> Listing
    {
        let held = self.held()
        var listing = Listing()
        for path in held.paths {
            let isPinned = held.pinned.contains(path)
            guard isPinned || listing.recent.count < limit,
                isPinned || showHidden || !Self.isHidden(path),
                let item = try? FileListing.item(
                    at: path, root: root, textExtensions: textExtensions)
            else { continue }
            if isPinned {
                listing.pinned.append(item)
            } else {
                listing.recent.append(item)
            }
        }
        return listing
    }

    /// Whether the item, or a folder it's in, is hidden.
    static func isHidden(_ path: FilePath) -> Bool {
        return path.components.contains { $0.hasPrefix(".") }
    }
}

/// Why Recents refused a change.
enum RecentsError: LocalizedError, Equatable {
    case tooManyPins

    var errorDescription: String? {
        switch self {
        case .tooManyPins:
            return String(localized: "Only 3 items can be pinned. Unpin one to pin this.")
        }
    }
}

/// Settings › History.
enum RecentsSettings {
    static let showLastKey = "recents.showLast"
    static let showLastDefault = 5
    static let showLastChoices = [3, 5, 10, 20]

    static func showLast(in defaults: UserDefaults = .standard) -> Int {
        let count = defaults.integer(forKey: showLastKey)
        return count > 0 ? count : showLastDefault
    }
}

extension FilesRoot {
    /// Notes that the item was opened, for Recents.
    static func opened(_ path: FilePath) {
        let operations = self.operations
        Task { await operations.recordOpen(path) }
    }
}

extension FileOperations {
    /// Recents in `stores`.
    nonisolated var recents: Recents { Recents(url: FilesStores.recents(in: stores)) }

    /// Puts `path` first, as it's just been opened. A failure to write leaves
    /// Recents as it was, which is all it costs.
    func recordOpen(_ path: FilePath) {
        var held = recents.held().changing { $0.filter(exists) }
        held.paths = [path] + held.paths.filter { $0 != path }
        try? recents.write(held.trimmed())
    }

    func hideRecent(_ path: FilePath) throws {
        try recents.write(recents.held().changing { $0.filter { $0 != path } })
    }

    /// Pins an item in Recents, unless `pinLimit` are pinned already.
    func pin(_ path: FilePath) throws {
        var held = recents.held().changing { $0.filter(exists) }
        guard !held.pinned.contains(path) else { return }
        guard held.pinned.count < Recents.pinLimit else { throw RecentsError.tooManyPins }
        if !held.paths.contains(path) { held.paths.insert(path, at: 0) }
        held.pinned.append(path)
        try recents.write(held)
    }

    /// Unpins an item, which then takes its place among the others by when it
    /// was opened.
    func unpin(_ path: FilePath) throws {
        var held = recents.held()
        held.pinned.removeAll { $0 == path }
        try recents.write(held.trimmed())
    }

    /// Changes what Recents holds after Files has changed the items, dropping
    /// any gone meanwhile. A failure to write leaves it as it was: missing
    /// items are skipped when read.
    func updateRecents(_ change: ([FilePath]) -> [FilePath]) {
        let held = recents.held()
        guard !held.paths.isEmpty else { return }
        let updated = held.changing { change($0).filter(exists) }
        if updated != held { try? recents.write(updated) }
    }
}
