import Foundation
import Testing

@testable import DialectCompanion

/// A fresh directory for the cache.
final class CacheDirectory: Sendable {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "FilesCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    var fileCount: Int {
        let names = try? FileManager.default.contentsOfDirectory(
            atPath: url.path(percentEncoded: false))
        return names?.count ?? 0
    }

    var total: Int {
        let names =
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return names.reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }
}

extension FilePath {
    /// A path written as `scripts/prelude.scm`; empty for the root.
    init(_ string: String) {
        self.init(components: string.split(separator: "/").map(String.init))
    }
}

struct FilesCacheTests {
    private let directory = CacheDirectory()
    private let seen = Date(timeIntervalSince1970: 1_790_000_000)

    private func cache(bound: Int = FilesCache.defaultBound, epoch: String? = "A") async
        -> FilesCache
    {
        let cache = FilesCache(bound: bound)
        await cache.use(directory: directory.url)
        await cache.use(epoch: epoch)
        return cache
    }

    /// A folder of `items` entries.
    private func folder(items: Int = 1, name: String = "a") -> CachedFolder {
        return CachedFolder(
            items: (0..<items).map {
                ListedItem(
                    name: "\(name) \($0)", kind: .text, size: 1, created: nil, modified: seen,
                    isReadOnly: false)
            }, settings: FolderViewSettings(sort: .size), token: "T", sizes: [FilePath("x"): 3],
            seen: seen)
    }

    // MARK: Round trips

    @Test func keepsAFolderRecentsAndTheBin() async throws {
        let cache = await cache()
        let notes = FilePath("notes")
        #expect(await cache.folder(notes) == nil)
        #expect(await cache.recents() == nil)
        #expect(await cache.bin() == nil)

        await cache.store(folder(), at: notes, epoch: "A")
        #expect(await cache.folder(notes) == folder())

        let item = FileItem(
            path: FilePath("a.md"), kind: .text, isDirectory: false, size: 1, created: nil,
            modified: nil, isReadOnly: false)
        let recents = CachedRecents(pinned: [item], recent: [], seen: seen)
        await cache.store(recents, epoch: "A")
        #expect(await cache.recents() == recents)

        let bin = CachedBin(
            items: [
                ListedBinItem(
                    id: UUID(), name: "a", original: FilePath("a"), deleted: seen, kind: .binary)
            ], token: "B", seen: seen)
        await cache.store(bin, epoch: "A")
        #expect(await cache.bin() == bin)

        // Another launch reads the same.
        let again = await self.cache()
        #expect(await again.folder(notes) == folder())
        #expect(await again.recents() == recents)
        #expect(await again.bin() == bin)
    }

    @Test func aDamagedFileReadsAsNone() async throws {
        let cache = await cache()
        let notes = FilePath("notes")
        await cache.store(folder(), at: notes, epoch: "A")
        let names = try FileManager.default.contentsOfDirectory(
            atPath: directory.url.path(percentEncoded: false))
        for name in names where name != "Index.json" {
            try Data("nope".utf8).write(to: directory.url.appending(path: name))
        }
        #expect(await cache.folder(notes) == nil)
    }

    /// With its index damaged, what's there can't be accounted for, so it goes.
    @Test func aDamagedIndexDropsEverything() async throws {
        let cache = await cache()
        await cache.store(folder(), at: FilePath("notes"), epoch: "A")
        try Data("nope".utf8).write(to: directory.url.appending(path: "Index.json"))
        let again = await self.cache()
        #expect(await again.folder(FilePath("notes")) == nil)
    }

    @Test func removesAFolder() async {
        let cache = await cache()
        await cache.store(folder(), at: FilePath("notes"), epoch: "A")
        await cache.remove(FilePath("notes"))
        #expect(await cache.folder(FilePath("notes")) == nil)
    }

    // MARK: The bound

    /// Sizes the bound so that about `count` folders of `items` fit.
    private func bound(count: Int, items: Int) throws -> Int {
        let one = try FilesCoding.encode(folder(items: items)).count
        return one * count + 2000
    }

    @Test func dropsTheLeastRecentlyShownFirst() async throws {
        let cache = await cache(bound: try bound(count: 3, items: 100))
        let paths = ["a", "b", "c", "d"].map(FilePath.init)
        for (index, path) in paths.enumerated() {
            await cache.store(folder(items: 100), at: path, epoch: "A", now: seen + Double(index))
        }
        #expect(await cache.folder(paths[0]) == nil)
        for path in paths[1...] { #expect(await cache.folder(path) != nil) }
    }

    @Test func showingAFolderProtectsIt() async throws {
        let cache = await cache(bound: try bound(count: 3, items: 100))
        let paths = ["a", "b", "c", "d"].map(FilePath.init)
        for (index, path) in paths.prefix(3).enumerated() {
            await cache.store(folder(items: 100), at: path, epoch: "A", now: seen + Double(index))
        }
        await cache.shown(paths[0], now: seen + 10)
        await cache.store(folder(items: 100), at: paths[3], epoch: "A", now: seen + 11)
        #expect(await cache.folder(paths[0]) != nil)
        #expect(await cache.folder(paths[1]) == nil)
    }

    @Test func theFolderOnScreenSurvivesEviction() async throws {
        let cache = await cache(bound: try bound(count: 2, items: 100))
        let paths = ["a", "b", "c", "d"].map(FilePath.init)
        await cache.keep(onScreen: [paths[0]])
        for (index, path) in paths.enumerated() {
            await cache.store(folder(items: 100), at: path, epoch: "A", now: seen + Double(index))
        }
        #expect(await cache.folder(paths[0]) != nil)
        #expect(await cache.folder(paths[1]) == nil)
    }

    /// Recents, the bin and the index count too, whatever fills it.
    @Test func everythingCountsTowardTheBound() async throws {
        let oneFolder = try FilesCoding.encode(folder(items: 50)).count
        let bound = oneFolder * 3
        let cache = await cache(bound: bound)
        let item = FileItem(
            path: FilePath(String(repeating: "x", count: 200)), kind: .text, isDirectory: false,
            size: 1, created: nil, modified: nil, isReadOnly: false)
        for (index, name) in ["a", "b", "c", "d", "e"].enumerated() {
            await cache.store(
                folder(items: 50), at: FilePath(name), epoch: "A", now: seen + Double(index))
        }
        await cache.store(
            CachedRecents(
                pinned: [], recent: Array(repeating: item, count: oneFolder / 300), seen: seen),
            epoch: "A")
        #expect(directory.total <= bound)
        #expect(await cache.recents() != nil)
    }

    // MARK: The epoch

    @Test func anotherEpochDropsEverything() async throws {
        let cache = await cache()
        await cache.store(folder(), at: FilePath("notes"), epoch: "A")
        await cache.store(CachedRecents(pinned: [], recent: [], seen: seen), epoch: "A")
        await cache.use(epoch: "B")
        #expect(await cache.folder(FilePath("notes")) == nil)
        #expect(await cache.recents() == nil)
        #expect(directory.fileCount == 1)
    }

    @Test func anotherEpochAtLaunchDropsEverything() async throws {
        let cache = await cache()
        await cache.store(folder(), at: FilePath("notes"), epoch: "A")

        let launched = await self.cache(epoch: "B")
        #expect(await launched.folder(FilePath("notes")) == nil)
    }

    /// A read begun under the old epoch stores nothing under the new one.
    @Test func aWriteInFlightDoesntSurviveAnEpochChange() async {
        let cache = await cache()
        await cache.use(epoch: "B")
        await cache.store(folder(), at: FilePath("notes"), epoch: "A")
        await cache.store(CachedRecents(pinned: [], recent: [], seen: seen), epoch: "A")
        await cache.store(CachedBin(items: [], token: "", seen: seen), epoch: "A")
        #expect(await cache.folder(FilePath("notes")) == nil)
        #expect(await cache.recents() == nil)
        #expect(await cache.bin() == nil)
    }

    @Test func noEpochYetChangesNothing() async {
        let cache = await cache()
        await cache.store(folder(), at: FilePath("notes"), epoch: "A")
        await cache.use(epoch: nil)
        #expect(await cache.folder(FilePath("notes")) != nil)
    }

    // MARK: The directory

    @Test func isExcludedFromBackup() async throws {
        _ = await cache()
        let values = try directory.url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func withoutADirectoryNothingIsKeptAndNothingThrows() async {
        let cache = FilesCache()
        await cache.use(directory: nil)
        await cache.use(epoch: "A")
        await cache.store(folder(), at: FilePath("notes"), epoch: "A")
        await cache.shown(FilePath("notes"))
        await cache.remove(FilePath("notes"))
        await cache.store(CachedRecents(pinned: [], recent: [], seen: seen), epoch: "A")
        #expect(await cache.folder(FilePath("notes")) == nil)
        #expect(await cache.recents() == nil)
        #expect(await cache.bin() == nil)
    }

    /// A directory gone since (another watch) stops anything being read from
    /// it.
    @Test func followsTheDirectory() async {
        let cache = await cache()
        await cache.store(folder(), at: FilePath("notes"), epoch: "A")
        await cache.use(directory: nil)
        #expect(await cache.folder(FilePath("notes")) == nil)

        let other = CacheDirectory()
        await cache.use(directory: other.url)
        await cache.use(epoch: "A")
        #expect(await cache.folder(FilePath("notes")) == nil)
    }
}
