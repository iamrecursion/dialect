import Foundation
import Testing

@testable import Dialect

/// Folders' and sessions' totals, worked out in the background.
struct FolderSizesTests {
    private func total(_ root: TemporaryRoot, _ path: String) async -> Int64? {
        return await FolderSizes().size(of: root.url.appending(path: path), modified: nil)
    }

    @Test func addsUpANestedTree() async throws {
        let root = try TemporaryRoot()
        try root.file("tree/a.txt", Data(count: 100))
        try root.file("tree/sub/b.txt", Data(count: 20))
        try root.file("tree/sub/deeper/c.txt", Data(count: 3))
        try root.file("tree/.hidden", Data(count: 4000))
        try root.folder("tree/empty")
        #expect(await total(root, "tree") == 4123)
        #expect(await total(root, "tree/empty") == 0)
        #expect(await total(root, "gone") == 0)
    }

    /// A link back up the tree would loop forever if followed.
    @Test func doesntFollowSymbolicLinks() async throws {
        let root = try TemporaryRoot()
        try root.file("tree/a.txt", Data(count: 10))
        try root.file("elsewhere/big.bin", Data(count: 5000))
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "tree/loop"), withDestinationURL: root.url)
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "tree/big.bin"),
            withDestinationURL: root.url.appending(path: "elsewhere/big.bin"))
        #expect(await total(root, "tree") == 10)
    }

    /// A link to a folder, as a row shows it, has the folder's total; links
    /// inside are still not followed.
    @Test func followsALinkToTheFolderItself() async throws {
        let root = try TemporaryRoot()
        try root.file("real/a.txt", Data(count: 7))
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "link"),
            withDestinationURL: root.url.appending(path: "real"))
        #expect(await total(root, "link") == 7)
    }

    /// Forgetting a changed item drops the totals of every folder above it, and
    /// keeps the rest.
    @Test func forgetsTheFoldersAboveAnItem() async throws {
        let root = try TemporaryRoot()
        try root.file("a/b/c/one.txt", Data(count: 1))
        try root.file("other/one.txt", Data(count: 1))
        let sizes = FolderSizes()
        let folders = ["a", "a/b", "a/b/c", "other"].map { root.url.appending(path: $0) }
        for folder in folders {
            #expect(await sizes.size(of: folder, modified: nil) == 1)
        }
        try root.file("a/b/c/two.txt", Data(count: 2))
        try root.file("other/two.txt", Data(count: 2))
        await sizes.forget(containing: root.url.appending(path: "a/b/c/two.txt"))
        for folder in folders.prefix(3) {
            #expect(await sizes.size(of: folder, modified: nil) == 3)
        }
        #expect(await sizes.size(of: folders[3], modified: nil) == 1)
    }

    /// A folder renamed away and back again keeps nothing stale from inside it.
    @Test func forgetsTheFoldersInsideAnItem() async throws {
        let root = try TemporaryRoot()
        try root.file("a/b/one.txt", Data(count: 1))
        let sizes = FolderSizes()
        let inner = root.url.appending(path: "a/b")
        #expect(await sizes.size(of: inner, modified: nil) == 1)
        try root.file("a/b/two.txt", Data(count: 2))
        await sizes.forget(containing: root.url.appending(path: "a"))
        #expect(await sizes.size(of: inner, modified: nil) == 3)
    }

    /// A walk given up part way gives no total, and isn't cached as one.
    @Test func aCancelledWalkGivesNothing() async throws {
        let root = try TemporaryRoot()
        try root.file("tree/a.txt", Data(count: 10))
        let sizes = FolderSizes()
        let folder = root.url.appending(path: "tree")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await sizes.size(of: folder, modified: nil)
        }
        #expect(await cancelled.value == nil)
        #expect(await sizes.size(of: folder, modified: nil) == 10)
    }

    /// Keyed by the modification date it was asked with: the old total stands
    /// until that changes.
    @Test func cachesUntilTheModificationDateChanges() async throws {
        let root = try TemporaryRoot()
        let folder = try root.folder("tree")
        try root.file("tree/a.txt", Data(count: 10))
        let sizes = FolderSizes()
        let first = Date(timeIntervalSince1970: 1)
        #expect(await sizes.size(of: folder, modified: first) == 10)

        try root.file("tree/b.txt", Data(count: 5))
        #expect(await sizes.size(of: folder, modified: first) == 10)
        #expect(await sizes.size(of: folder, modified: Date(timeIntervalSince1970: 2)) == 15)
    }
}
