import Foundation

/// A folder, from the watch's last answer.
struct CachedFolder: Codable, Equatable, Sendable {
    var items: [ListedItem]
    var settings: FolderViewSettings
    var token: String

    /// Totals of the folders and sessions in it, as far as they've been asked
    /// for.
    var sizes: [FilePath: Int64] = [:]

    /// When the watch last said this was so.
    var seen: Date
}

struct CachedRecents: Codable, Equatable, Sendable {
    var pinned: [FileItem]
    var recent: [FileItem]
    var seen: Date
}

struct CachedBin: Codable, Equatable, Sendable {
    var items: [ListedBinItem]
    var token: String
    var seen: Date
}

/// What the phone remembers of the watch's Files: metadata only, never
/// contents: one JSON file per folder, Recents, the bin, and an index of them.
/// It lives in the session's directory for the watch.
///
/// Everything in it counts toward the bound; past that the folders shown least
/// recently go, never one on screen. It's dropped whole when the watch's epoch
/// changes. Without a directory, nothing is kept. An actor, so writing never
/// blocks the screen.
actor FilesCache {
    static let defaultBound = 50 * 1024 * 1024

    private struct Index: Codable {
        var format = 1
        var epoch: String?
        var folders: [String: Entry] = [:]

        struct Entry: Codable {
            var path: FilePath
            var size: Int
            var shown: Date
        }
    }

    private let bound: Int
    private var directory: URL?
    private var index = Index()
    private var onScreen: Set<FilePath> = []

    init(bound: Int = FilesCache.defaultBound) {
        self.bound = bound
    }

    // MARK: Where and for which Dialect

    /// Follows the session's directory for the watch, reading what's there.
    func use(directory: URL?) {
        guard directory != self.directory else { return }
        self.directory = directory
        onScreen = []
        index = Index()
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        if let data = try? Data(contentsOf: indexURL(in: directory)),
            let read = try? FilesCoding.decode(Index.self, from: data)
        {
            index = read
        } else {
            removeEverything(in: directory)
        }
    }

    /// A reinstalled Dialect has another epoch and other files: all of this
    /// goes, including what a read begun under the old epoch would still store.
    func use(epoch: String?) {
        guard let epoch, epoch != index.epoch else { return }
        if index.epoch != nil, let directory { removeEverything(in: directory) }
        index = Index(epoch: epoch)
        writeIndex()
    }

    /// The folders on screen, which nothing evicts.
    func keep(onScreen paths: Set<FilePath>) {
        onScreen = paths
    }

    // MARK: Folders

    func folder(_ path: FilePath) -> CachedFolder? {
        guard let directory else { return nil }
        return read(CachedFolder.self, at: folderURL(path, in: directory))
    }

    /// Dropped if the epoch has changed since `epoch`, when the read began.
    func store(_ folder: CachedFolder, at path: FilePath, epoch: String?, now: Date = Date()) {
        guard let directory, epoch == index.epoch,
            let data = try? FilesCoding.encode(folder)
        else { return }
        let url = folderURL(path, in: directory)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        index.folders[url.lastPathComponent] = Index.Entry(
            path: path, size: data.count, shown: now)
        evict(in: directory)
        writeIndex()
    }

    /// Notes that a folder was shown, which keeps it longer.
    func shown(_ path: FilePath, now: Date = Date()) {
        guard let directory else { return }
        let name = folderURL(path, in: directory).lastPathComponent
        guard index.folders[name] != nil else { return }
        index.folders[name]?.shown = now
        writeIndex()
    }

    func remove(_ path: FilePath) {
        guard let directory else { return }
        let url = folderURL(path, in: directory)
        try? FileManager.default.removeItem(at: url)
        index.folders[url.lastPathComponent] = nil
        writeIndex()
    }

    // MARK: Recents and the bin

    func recents() -> CachedRecents? {
        return directory.flatMap { read(CachedRecents.self, at: recentsURL(in: $0)) }
    }

    func store(_ recents: CachedRecents, epoch: String?) {
        guard let directory, epoch == index.epoch else { return }
        write(recents, to: recentsURL(in: directory), in: directory)
    }

    func bin() -> CachedBin? {
        return directory.flatMap { read(CachedBin.self, at: binURL(in: $0)) }
    }

    func store(_ bin: CachedBin, epoch: String?) {
        guard let directory, epoch == index.epoch else { return }
        write(bin, to: binURL(in: directory), in: directory)
    }

    // MARK: Files

    private func indexURL(in directory: URL) -> URL {
        return directory.appending(path: "Index.json", directoryHint: .notDirectory)
    }

    private func recentsURL(in directory: URL) -> URL {
        return directory.appending(path: "Recents.json", directoryHint: .notDirectory)
    }

    private func binURL(in directory: URL) -> URL {
        return directory.appending(path: "Bin.json", directoryHint: .notDirectory)
    }

    /// Named by a hash, as a path can be longer than a file's name may be.
    private func folderURL(_ path: FilePath, in directory: URL) -> URL {
        let encoded = (try? FilesCoding.encode(path)) ?? Data()
        return directory.appending(
            path: FilesPaging.token(of: [encoded]) + ".json", directoryHint: .notDirectory)
    }

    /// What can't be read counts as nothing.
    private func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? FilesCoding.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL, in directory: URL) {
        guard let data = try? FilesCoding.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
        evict(in: directory)
        writeIndex()
    }

    private func writeIndex() {
        guard let directory, let data = try? FilesCoding.encode(index) else { return }
        try? data.write(to: indexURL(in: directory), options: .atomic)
    }

    private func removeEverything(in directory: URL) {
        let names =
            (try? FileManager.default.contentsOfDirectory(
                atPath: directory.path(percentEncoded: false))) ?? []
        for name in names {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    // MARK: The bound

    private func size(of url: URL) -> Int {
        return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    /// Everything kept, the index as it'll be written included.
    private func used(in directory: URL) -> Int {
        let index = (try? FilesCoding.encode(index))?.count ?? 0
        let folders = self.index.folders.values.reduce(0) { $0 + $1.size }
        return index + folders + size(of: recentsURL(in: directory))
            + size(of: binURL(in: directory))
    }

    private func evict(in directory: URL) {
        let oldestFirst = index.folders.sorted { $0.value.shown < $1.value.shown }
        for (name, entry) in oldestFirst where !onScreen.contains(entry.path) {
            guard used(in: directory) > bound else { return }
            try? FileManager.default.removeItem(at: directory.appending(path: name))
            index.folders[name] = nil
        }
    }
}
