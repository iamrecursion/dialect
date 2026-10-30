import Foundation

/// The totals of folders and sessions, worked out in the background and cached.
///
/// The cache is keyed by the folder and its modification date. A folder's date
/// changes only when its entries do, so a change deeper down made elsewhere,
/// such as by the REPL, shows on the next launch.
actor FolderSizes {
    static let shared = FolderSizes()

    private var cache: [URL: (modified: Date?, size: Int64)] = [:]

    /// Walks that outlive whoever started them, for later requests to join.
    private var walks: [URL: Walk] = [:]

    private struct Walk {
        let id: UUID
        let modified: Date?
        let total: Task<Int64?, Never>
    }

    /// Runs joinable walks one at a time, off Swift's thread pool, as a walk
    /// blocks its thread and a watch has few.
    private let walkQueue = DispatchQueue(label: "FolderSizes", qos: .utility)

    private let walker: @Sendable (URL, String?) -> Int64?

    init(walker: @escaping @Sendable (URL, String?) -> Int64? = FolderSizes.total) {
        self.walker = walker
    }

    /// The total, without the inbox at the root, or `nil` when the task asking
    /// was cancelled before the walk finished. The walk runs off the actor,
    /// which only keeps the cache.
    func size(of folder: FilePath, root: URL, modified: Date?) async -> Int64? {
        let url = folder.url(in: root)
        if let cached = cache[url], cached.modified == modified { return cached.size }
        guard let size = await Self.walk(url, skipping: Self.skipped(in: folder)) else {
            return nil
        }
        cache[url] = (modified, size)
        return size
    }

    /// As `size(of:root:modified:)`, but the walk doesn't belong to the task
    /// asking, which waits for it at most `wait`: past that, the answer is
    /// `nil`, and the walk goes on for a later request to find or join.
    func size(of folder: FilePath, root: URL, modified: Date?, within wait: Duration) async
        -> Int64?
    {
        let url = folder.url(in: root)
        if let cached = cache[url], cached.modified == modified { return cached.size }
        let total = joined(url, skipping: Self.skipped(in: folder), modified: modified)
        return
            (try? await withCheckedThrowingContinuation { continuation in
                let answer = OneShot<Int64?>(continuation)
                Task { answer.finish(.success(await total.value)) }
                Task {
                    try? await Task.sleep(for: wait)
                    answer.finish(.success(nil))
                }
            }) ?? nil
    }

    /// The walk of `url` at this modification date, started if there's none.
    private func joined(_ url: URL, skipping: String?, modified: Date?) -> Task<Int64?, Never> {
        if let walk = walks[url], walk.modified == modified { return walk.total }
        let id = UUID()
        let total = Task { [weak self, walker, walkQueue] () -> Int64? in
            let size = await withCheckedContinuation { continuation in
                walkQueue.async { continuation.resume(returning: walker(url, skipping)) }
            }
            await self?.finish(url, id: id, modified: modified, size: size)
            return size
        }
        walks[url] = Walk(id: id, modified: modified, total: total)
        return total
    }

    /// Keeps the total, unless it's been forgotten or overtaken meanwhile.
    private func finish(_ url: URL, id: UUID, modified: Date?, size: Int64?) {
        guard walks[url]?.id == id else { return }
        walks[url] = nil
        if let size { cache[url] = (modified, size) }
    }

    /// What a folder's total leaves out.
    private static func skipped(in folder: FilePath) -> String? {
        return folder == .root ? FilePath.inboxName : nil
    }

    /// Drops the totals of `url`, every folder above it and everything in it,
    /// after Files has changed something there.
    func forget(containing url: URL) {
        let changed = url.standardizedFileURL.pathComponents
        func isUnaffected(_ key: URL) -> Bool {
            let folder = key.standardizedFileURL.pathComponents
            return !changed.starts(with: folder) && !folder.starts(with: changed)
        }
        cache = cache.filter { isUnaffected($0.key) }
        walks = walks.filter { isUnaffected($0.key) }
    }

    @concurrent
    private static func walk(_ url: URL, skipping: String?) async -> Int64? {
        return total(of: url, skipping: skipping)
    }

    /// The bytes in every regular file below `url`, hidden ones included, but
    /// not the entry `skipping` directly in it. Sizes are logical, as rows show
    /// them, so a folder holding one file is as big as the file.
    static func total(of url: URL, skipping: String? = nil) -> Int64? {
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
            if enumerator.level == 1, file.lastPathComponent == skipping {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
