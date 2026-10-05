import Foundation
import Testing

@testable import Dialect

struct FilePathTests {
    @Test func root() {
        #expect(FilePath.root.components.isEmpty)
        #expect(FilePath.root.name == nil)
        #expect(FilePath.root.parent == nil)
        #expect(FilePath.root.display == "/")
    }

    @Test func appendsAndClimbs() {
        let prelude = FilePath.root.appending("scripts").appending("prelude.scm")
        #expect(prelude.components == ["scripts", "prelude.scm"])
        #expect(prelude.name == "prelude.scm")
        #expect(prelude.parent == FilePath(components: ["scripts"]))
        #expect(prelude.parent?.parent == .root)
        #expect(prelude.display == "/scripts/prelude.scm")
    }

    @Test func locatesItselfUnderARoot() {
        let root = URL(filePath: "/tmp/Documents", directoryHint: .isDirectory)
        #expect(FilePath.root.url(in: root).path(percentEncoded: false) == "/tmp/Documents/")
        #expect(
            FilePath(components: ["a b", "Café.md"]).url(in: root).path(percentEncoded: false)
                == "/tmp/Documents/a b/Café.md")
    }
}

/// Reading a folder: kinds, attributes, hidden items, and names that aren't
/// plain ASCII.
struct FileListingTests {
    private func list(_ root: TemporaryRoot, _ folder: FilePath = .root, hidden: Bool = false)
        throws -> [FileItem]
    {
        return try FileListing.items(
            in: folder, root: root.url, showHidden: hidden, textExtensions: [])
    }

    private func names(_ items: [FileItem]) -> [String] {
        return items.map(\.name).sorted()
    }

    @Test func listsAFolder() throws {
        let root = try TemporaryRoot()
        try root.file("scripts/prelude.scm", text: "(define x 1)")
        try root.file("notes.md", text: "# Notes")
        try root.folder("demo.dial")
        try root.file("readme", text: "Read me")
        try root.file("blob.bin", Data([0, 1, 2]))

        let items = try list(root)
        #expect(names(items) == ["blob.bin", "demo.dial", "notes.md", "readme", "scripts"])
        let kinds = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.kind) })
        #expect(kinds["scripts"] == .folder)
        #expect(kinds["demo.dial"] == .session)
        #expect(kinds["notes.md"] == .text)
        #expect(kinds["readme"] == .otherText)
        #expect(kinds["blob.bin"] == .binary)

        let inner = try list(root, FilePath(components: ["scripts"]))
        #expect(inner.map(\.path) == [FilePath(components: ["scripts", "prelude.scm"])])
        #expect(inner.first?.kind == .scheme)
    }

    @Test func hidesDotfilesUnlessAsked() throws {
        let root = try TemporaryRoot()
        try root.file(".hidden-config", text: "x")
        try root.folder(".cache")
        try root.file("shown.txt")

        #expect(names(try list(root)) == ["shown.txt"])
        let all = try list(root, hidden: true)
        #expect(names(all) == [".cache", ".hidden-config", "shown.txt"])
        #expect(all.filter(\.isHidden).count == 2)
    }

    @Test func readsSizesAndDates() throws {
        let root = try TemporaryRoot()
        let file = try root.file("data.json", Data(repeating: 0x20, count: 1234))
        let then = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: then], ofItemAtPath: file.path)
        try root.folder("folder")

        let items = try list(root)
        let data = try #require(items.first { $0.name == "data.json" })
        #expect(data.size == 1234)
        #expect(data.modified == then)
        #expect(data.created != nil)
        #expect(!data.isDirectory)
        #expect(!data.isReadOnly)

        let folder = try #require(items.first { $0.name == "folder" })
        #expect(folder.isDirectory)
        #expect(folder.size == nil)
    }

    @Test func reportsReadOnlyFiles() throws {
        let root = try TemporaryRoot()
        let file = try root.file("locked.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: file.path)
        }
        #expect(try list(root).first?.isReadOnly == true)
    }

    @Test func usesTheUsersTextExtensions() throws {
        let root = try TemporaryRoot()
        try root.file("init.el", Data([0, 0]))
        let items = try FileListing.items(
            in: .root, root: root.url, showHidden: false, textExtensions: ["el"])
        #expect(items.first?.kind == .text)
    }

    /// APFS keeps a name's normalization form, and a path built from a listed
    /// name must reach the same file.
    @Test func reopensNamesThatArentASCII() throws {
        let root = try TemporaryRoot()
        try root.file("Café.md", text: "café")
        try root.file("Cafe\u{301}2.md", text: "decomposed")
        try root.folder("🙂 folder")
        try root.file("🙂 folder/🙂.scm", text: "(display \"🙂\")")

        let items = try list(root)
        #expect(items.count == 3)
        for item in items where !item.isDirectory {
            #expect(FileManager.default.fileExists(atPath: item.path.url(in: root.url).path))
        }
        let folder = try #require(items.first { $0.isDirectory })
        let inner = try list(root, folder.path)
        #expect(inner.first?.kind == .scheme)
        #expect(
            try String(
                contentsOf: try #require(inner.first).path.url(in: root.url), encoding: .utf8)
                == "(display \"🙂\")")
    }

    /// A broken link is listed, as a binary file with nothing known about it.
    @Test func listsADanglingSymbolicLink() throws {
        let root = try TemporaryRoot()
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "dangling.scm"),
            withDestinationURL: root.url.appending(path: "nowhere.scm"))

        let item = try #require(try list(root).first)
        #expect(item.name == "dangling.scm")
        #expect(item.kind == .binary)
        #expect(item.size == nil)
        #expect(item.modified == nil)
        #expect(item.created == nil)
    }

    /// A link to a folder is a folder, and opens as one.
    @Test func listsThroughALinkToAFolder() throws {
        let root = try TemporaryRoot()
        try root.file("real/inside.md", text: "x")
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "link"),
            withDestinationURL: root.url.appending(path: "real"))
        let link = try #require(try list(root).first { $0.name == "link" })
        #expect(link.kind == .folder)
        let inside = try list(root, link.path)
        #expect(inside.map(\.path) == [FilePath(components: ["link", "inside.md"])])
        guard
            case .items(let items, _) = FolderLoader.load(
                link.path, root: root.url, showHidden: false, textExtensions: [])
        else {
            Issue.record("the linked folder didn't load")
            return
        }
        #expect(items.count == 1)
    }

    /// Anything that isn't a regular file, such as a named pipe, is never
    /// sniffed: opening a pipe waits for a writer.
    @Test func doesntOpenANamedPipe() throws {
        let root = try TemporaryRoot()
        let pipe = root.url.appending(path: "pipe")
        #expect(mkfifo(pipe.path(percentEncoded: false), 0o644) == 0)
        let item = try #require(try list(root).first)
        #expect(item.kind == .binary)
        #expect(!item.isDirectory)
    }

    @Test func throwsForAMissingFolder() throws {
        let root = try TemporaryRoot()
        #expect(throws: (any Error).self) {
            try list(root, FilePath(components: ["gone"]))
        }
    }

    @Test func readsOneItem() throws {
        let root = try TemporaryRoot()
        try root.file("notes/notes.md", text: "# Notes")
        let item = try FileListing.item(
            at: FilePath(components: ["notes", "notes.md"]), root: root.url, textExtensions: [])
        #expect(item.kind == .text)
        #expect(item.size == 7)

        let top = try FileListing.item(at: .root, root: root.url, textExtensions: [])
        #expect(top.kind == .folder)
        #expect(top.isDirectory)
    }
}

/// Names as rows and Info show them.
struct FileItemNameTests {
    private func item(_ name: String, _ kind: FileKind) -> FileItem {
        let isDirectory = kind == .folder || kind == .session
        return FileItem(
            path: FilePath(components: [name]), kind: kind, isDirectory: isDirectory, size: nil,
            created: nil, modified: nil, isReadOnly: false)
    }

    @Test func splitsNames() {
        let notes = item("notes.md", .text)
        #expect(notes.baseName == "notes")
        #expect(notes.pathExtension == "md")
        #expect(notes.displayName(showExtensions: true) == "notes.md")
        #expect(notes.displayName(showExtensions: false) == "notes")

        let archive = item("archive.tar.gz", .binary)
        #expect(archive.baseName == "archive.tar")
        #expect(archive.pathExtension == "gz")
    }

    @Test func sessionsShowTheirExtensionLikeFiles() {
        let demo = item("demo.dial", .session)
        #expect(demo.pathExtension == "dial")
        #expect(demo.displayName(showExtensions: true) == "demo.dial")
        #expect(demo.displayName(showExtensions: false) == "demo")
    }

    @Test func foldersNeverShowAnExtension() {
        let folder = item("v1.2", .folder)
        #expect(folder.pathExtension == "")
        #expect(folder.baseName == "v1.2")
        #expect(folder.displayName(showExtensions: true) == "v1.2")
        #expect(folder.displayName(showExtensions: false) == "v1.2")
    }

    /// A leading dot hides an item; it doesn't start an extension.
    @Test func dotfilesHaveNoExtension() {
        let config = item(".hidden-config", .otherText)
        #expect(config.pathExtension == "")
        #expect(config.baseName == ".hidden-config")
        #expect(config.isHidden)
        #expect(item(".config.json", .text).pathExtension == "json")
        #expect(item("trailing.", .otherText).pathExtension == "")
        #expect(item("readme", .otherText).displayName(showExtensions: true) == "readme")
    }
}
