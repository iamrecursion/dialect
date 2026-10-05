import Foundation
import Testing

@testable import Dialect

/// `-seedFiles`' sample tree: every kind, a session, hidden items, a deep path,
/// enough to scroll, and dates in every Modified bucket.
struct SeedFilesTests {
    private let now = Date()

    private func build() throws -> TemporaryRoot {
        let root = try TemporaryRoot()
        try SeedFiles.build(at: root.url, now: now)
        return root
    }

    private func names(_ root: TemporaryRoot, _ folder: [String] = [], hidden: Bool = false)
        throws -> [String]
    {
        return try FileListing.items(
            in: FilePath(components: folder), root: root.url, showHidden: hidden,
            textExtensions: []
        ).map(\.name).sorted()
    }

    @Test func buildsTheTree() throws {
        let root = try build()
        #expect(
            try names(root) == [
                "blob.bin", "demo.dial", "empty", "many", "media", "notes", "readme", "scripts",
            ])
        #expect(try names(root, ["scripts"]) == ["lib", "prelude.scm", "util.sld"])
        #expect(try names(root, ["scripts", "lib", "a", "b", "c", "d"]) == ["deep.scm"])
        #expect(
            try names(root, ["notes"]) == [
                "config.toml", "data.json", "feed.xml", "notes.md", "settings.yaml", "table.csv",
                "todo.txt",
            ])
        #expect(try names(root, ["media"]) == ["Photo.JPG", "clip.mp4", "photo.png"])
        #expect(try names(root, ["demo.dial"]) == ["main.scm", "manifest.json"])
        #expect(try names(root, ["many"]).count == 12)
        #expect(try names(root, ["empty"]).isEmpty)
        #expect(try names(root, hidden: true).contains(".hidden-config"))
        #expect(try names(root, hidden: true).contains(".cache"))
    }

    @Test func coversEveryKind() throws {
        let root = try build()
        var kinds = Set<FileKind>()
        for folder in [[], ["scripts"], ["notes"], ["media"]] {
            let items = try FileListing.items(
                in: FilePath(components: folder), root: root.url, showHidden: true,
                textExtensions: [])
            kinds.formUnion(items.map(\.kind))
        }
        #expect(kinds == Set(FileKind.allCases))
    }

    @Test func writesRealContents() throws {
        let root = try build()
        let manifest = try Data(contentsOf: root.url.appending(path: "demo.dial/manifest.json"))
        let json = try JSONSerialization.jsonObject(with: manifest) as? [String: Int]
        #expect(json == ["format": 1])
        let blob = try Data(contentsOf: root.url.appending(path: "blob.bin"))
        #expect(blob == Data(0...255))
        let png = try Data(contentsOf: root.url.appending(path: "media/photo.png"))
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let jpeg = try Data(contentsOf: root.url.appending(path: "media/Photo.JPG"))
        #expect(jpeg.starts(with: [0xFF, 0xD8]))
    }

    @Test func spreadsDatesAcrossTheBuckets() throws {
        let root = try build()
        var buckets = Set<ModifiedBucket>()
        for folder in [[], ["notes"]] {
            let items = try FileListing.items(
                in: FilePath(components: folder), root: root.url, showHidden: false,
                textExtensions: [])
            buckets.formUnion(items.map { FolderArrangement.bucket(for: $0.modified, now: now) })
        }
        #expect(buckets == Set(ModifiedBucket.allCases))
    }

    /// The bin holds what its tests need: an item to restore to its folder, one
    /// whose folder is gone, one whose place is taken, two namesakes, and one
    /// expired.
    @Test func seedsTheBin() throws {
        let root = try TemporaryRoot()
        let stores = try TemporaryRoot()
        try SeedFiles.build(at: root.url, stores: stores.url, now: now)
        let items = Bin(url: FilesStores.bin(in: stores.url)).items()
        let day: TimeInterval = 24 * 60 * 60
        let expected: [(String, String, TimeInterval)] = [
            ("readme", "readme", 3600),
            ("old-notes.md", "notes/old-notes.md", 2 * day),
            ("draft.scm", "scripts/draft.scm", 3 * day),
            ("draft 2.scm", "scripts/draft.scm", 5 * day),
            ("sketch.scm", "gone/sketch.scm", 10 * day),
            ("expired.txt", "expired.txt", 40 * day),
        ]
        #expect(items.map(\.name) == expected.map(\.0))
        #expect(items.map(\.original) == expected.map { FilePath($0.1) })
        for (item, (_, _, age)) in zip(items, expected) {
            #expect(abs(item.deleted.timeIntervalSince(now - age)) < 0.01, "\(item.name)")
        }
        #expect(try names(root).contains("readme"))
        #expect(try !names(root).contains("gone"))
        #expect(try !names(root, ["scripts"]).contains("draft.scm"))
    }

    /// The bin starts again from scratch too.
    @Test func rebuildsTheBinFromScratch() throws {
        let root = try TemporaryRoot()
        let stores = try TemporaryRoot()
        try SeedFiles.build(at: root.url, stores: stores.url, now: now)
        try SeedFiles.build(at: root.url, stores: stores.url, now: now)
        #expect(Bin(url: FilesStores.bin(in: stores.url)).items().count == 6)
    }

    /// It starts again from scratch, so a test never sees a previous run's
    /// leftovers.
    @Test func rebuildsFromScratch() throws {
        let root = try build()
        try root.file("leftover.txt")
        try SeedFiles.build(at: root.url, now: now)
        #expect(try !names(root).contains("leftover.txt"))
    }
}
