import Foundation
import Testing

@testable import Dialect

/// The text-like check outside the listing: unknown files are listed unchecked,
/// checked afterward, and the result kept until the file changes.
struct FileKindsTests {
    private func list(_ root: TemporaryRoot, _ kinds: FileKinds) throws -> [String: FileItem] {
        let items = try FileListing.items(
            in: .root, root: root.url, showHidden: false, textExtensions: [], checking: kinds)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
    }

    @Test func listsUnknownFilesUnchecked() throws {
        let root = try TemporaryRoot()
        try root.file("readme", text: "Read me")
        try root.file("blob.bin", Data([0, 1, 2]))
        try root.file("notes.md", text: "# Notes")

        let items = try list(root, FileKinds())
        #expect(items["readme"]?.kind == .otherText)
        #expect(items["readme"]?.needsCheck == true)
        // Listed as a Document until checked.
        #expect(items["blob.bin"]?.kind == .otherText)
        #expect(items["blob.bin"]?.needsCheck == true)
        // Its extension decides it.
        #expect(items["notes.md"]?.kind == .text)
        #expect(items["notes.md"]?.needsCheck == false)
    }

    @Test func listsWhatItHasCheckedAtOnce() throws {
        let root = try TemporaryRoot()
        try root.file("blob.bin", Data([0, 1, 2]))
        let kinds = FileKinds()
        let unchecked = try #require(try list(root, kinds)["blob.bin"])
        #expect(kinds.check(unchecked, root: root.url) == .binary)

        let listed = try #require(try list(root, kinds)["blob.bin"])
        #expect(listed.kind == .binary)
        #expect(!listed.needsCheck)
    }

    /// A file changed since it was checked is checked again.
    @Test func checksAChangedFileAgain() throws {
        let root = try TemporaryRoot()
        try root.file("blob.bin", Data([0, 1, 2]))
        let kinds = FileKinds()
        _ = kinds.check(try #require(try list(root, kinds)["blob.bin"]), root: root.url)

        try root.file("blob.bin", text: "Now it's text, and longer")
        let changed = try #require(try list(root, kinds)["blob.bin"])
        #expect(changed.needsCheck)
        #expect(kinds.check(changed, root: root.url) == .otherText)
    }

    /// A folder reached through a link lists its files under the link's target,
    /// and still finds what was checked.
    @Test func keepsWhatItCheckedThroughALink() throws {
        let root = try TemporaryRoot()
        try root.file("real/blob.bin", Data([0, 1, 2]))
        try FileManager.default.createSymbolicLink(
            atPath: root.url.appending(path: "link").path(percentEncoded: false),
            withDestinationPath: "real")
        let kinds = FileKinds()
        let link = FilePath(components: ["link"])
        func listed() throws -> FileItem {
            return try #require(
                try FileListing.items(
                    in: link, root: root.url, showHidden: false, textExtensions: [],
                    checking: kinds
                ).first)
        }
        #expect(kinds.check(try listed(), root: root.url) == .binary)
        let again = try listed()
        #expect(again.kind == .binary)
        #expect(!again.needsCheck)
    }

    /// Something that's no longer a regular file is never opened.
    @Test func doesntOpenWhatBecameAPipe() throws {
        let root = try TemporaryRoot()
        try root.file("data", text: "text")
        let item = try #require(try list(root, FileKinds())["data"])
        let url = root.url.appending(path: "data")
        try FileManager.default.removeItem(at: url)
        #expect(mkfifo(url.path(percentEncoded: false), 0o644) == 0)
        #expect(FileKinds().check(item, root: root.url) == .binary)
    }

    @Test func givesTheItemItsCheckedKind() throws {
        let root = try TemporaryRoot()
        try root.file("blob.bin", Data([0, 1, 2]))
        let item = try #require(try list(root, FileKinds())["blob.bin"])
        let checked = item.checked(as: .binary)
        #expect(checked.kind == .binary)
        #expect(!checked.needsCheck)
        #expect(checked.path == item.path)
        #expect(checked.size == item.size)
    }
}
