import Foundation

/// Paths, for Paste and Move to act on.
///
/// Reading never writes, so screens can read it off the actor; only
/// `FileOperations` changes it.
struct Clipboard: Sendable {
    /// The file it's kept in, written whole each time, so a reader never sees
    /// half of it.
    let url: URL

    private struct Record: Codable {
        var format = 1
        var items: [[String]]
    }

    /// What it holds, gone or not; nothing when its file can't be read.
    func paths() -> [FilePath] {
        guard let data = try? Data(contentsOf: url),
            let record = try? JSONDecoder().decode(Record.self, from: data)
        else { return [] }
        return record.items.map(FilePath.init(components:))
    }

    func write(_ paths: [FilePath]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let record = Record(items: paths.map(\.components))
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }

    /// The items still there, in its order.
    func items(root: URL, textExtensions: Set<String>) -> [FileItem] {
        return paths().compactMap {
            try? FileListing.item(at: $0, root: root, textExtensions: textExtensions)
        }
    }

    /// The paths still there, in its order.
    func existing(root: URL) -> [FilePath] {
        return paths().filter { Self.exists($0, in: root) }
    }

    /// Whether something is at `path`; a link counts, even a broken one.
    static func exists(_ path: FilePath, in root: URL) -> Bool {
        return
            (try? FileManager.default.attributesOfItem(
                atPath: path.url(in: root).path(percentEncoded: false))) != nil
    }
}

extension Array where Element == FilePath {
    /// Rewritten for `old` having become `new`: it and everything inside it.
    func following(_ old: FilePath, to new: FilePath) -> [FilePath] {
        return map { path in
            guard path.isWithin(old) else { return path }
            return FilePath(
                components: new.components + path.components.dropFirst(old.components.count))
        }
    }

    /// Without `item` and everything inside it.
    func dropping(within item: FilePath) -> [FilePath] {
        return filter { !$0.isWithin(item) }
    }
}

extension FileOperations {
    /// The clipboard in `stores`.
    nonisolated var clipboard: Clipboard { Clipboard(url: FilesStores.clipboard(in: stores)) }

    /// Puts `paths` on the clipboard in place of what it held.
    func copy(_ paths: [FilePath]) throws {
        var unique: [FilePath] = []
        for path in paths where !unique.contains(path) { unique.append(path) }
        try clipboard.write(unique)
    }

    func clearClipboard() throws {
        try clipboard.write([])
    }

    /// Drops what's gone from the clipboard and Recents, before Files places
    /// anything that could take a path either holds.
    func pruneHeld() {
        updateClipboard { $0 }
        updateRecents { $0 }
    }

    /// Changes what the clipboard holds after Files has changed the items,
    /// dropping any gone meanwhile. A failure to write leaves it as it was:
    /// missing items drop off when read.
    func updateClipboard(_ change: ([FilePath]) -> [FilePath]) {
        let clipboard = self.clipboard
        let held = clipboard.paths()
        guard !held.isEmpty else { return }
        let updated = change(held).filter(exists)
        if updated != held { try? clipboard.write(updated) }
    }

    func exists(_ path: FilePath) -> Bool {
        return Clipboard.exists(path, in: root)
    }
}
