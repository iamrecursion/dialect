import Foundation

/// The totals of folders and sessions, worked out in the background and cached.
///
/// The cache is keyed by the folder and its modification date. A folder's date
/// changes only when its entries do, so a change deeper down made elsewhere,
/// such as by the REPL, shows on the next launch.
actor FolderSizes {
    static let shared = FolderSizes()

    private var cache: [URL: (modified: Date?, size: Int64)] = [:]

    /// The total, or `nil` when the task asking was cancelled before the walk
    /// finished. The walk runs off the actor, which only keeps the cache.
    func size(of url: URL, modified: Date?) async -> Int64? {
        if let cached = cache[url], cached.modified == modified { return cached.size }
        guard let size = await Self.walk(url) else { return nil }
        cache[url] = (modified, size)
        return size
    }

    /// Drops the totals of `url`, every folder above it and everything in it,
    /// after Files has changed something there.
    func forget(containing url: URL) {
        let changed = url.standardizedFileURL.pathComponents
        cache = cache.filter { key, _ in
            let folder = key.standardizedFileURL.pathComponents
            return !changed.starts(with: folder) && !folder.starts(with: changed)
        }
    }

    @concurrent
    private static func walk(_ url: URL) async -> Int64? {
        return total(of: url)
    }

    /// The bytes in every regular file below `url`, hidden ones included. Sizes
    /// are logical, as rows show them, so a folder holding one file is as big
    /// as the file.
    static func total(of url: URL) -> Int64? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard !Task.isCancelled else { return nil }
        guard
            let enumerator = FileManager.default.enumerator(
                at: url.resolvingSymlinksInPath(), includingPropertiesForKeys: keys,
                errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            if Task.isCancelled { return nil }
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

/// Sizes as rows and Info show them.
enum SizeDisplay {
    /// "—" while a folder's total is still being worked out.
    static func string(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
