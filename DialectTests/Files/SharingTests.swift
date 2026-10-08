import Foundation
import Testing

@testable import Dialect

/// What Share sends: names, gathering a folder with its links, zips, and the
/// `Sharing` folder's cleanup.
struct SharingTests {
    private let root: TemporaryRoot
    private let stores: TemporaryRoot

    init() throws {
        root = try TemporaryRoot()
        stores = try TemporaryRoot()
    }

    // MARK: Names

    @Test func sendsAFileAsItselfAndAFolderOrSeveralZipped() {
        let folders: Set<FilePath> = [FilePath("notes"), FilePath("demo.dial")]
        func shared(_ paths: [String]) -> Shared? {
            return Shared.of(paths.map(FilePath.init)) { folders.contains($0) }
        }
        #expect(shared(["notes/todo.txt"]) == .file(FilePath("notes/todo.txt")))
        #expect(shared(["notes"]) == .archive([FilePath("notes")], name: "notes.zip"))
        #expect(shared(["demo.dial"]) == .archive([FilePath("demo.dial")], name: "demo.dial.zip"))
        #expect(
            shared(["readme", "notes"])
                == .archive([FilePath("readme"), FilePath("notes")], name: "Archive.zip"))
        #expect(shared([]) == nil)
        #expect(shared(["notes/todo.txt"])?.name == "todo.txt")
        #expect(shared(["notes"])?.name == "notes.zip")
    }

    // MARK: Gathering

    /// Links leading elsewhere inside the folder come as what they lead to;
    /// those leading out, back up, or nowhere are left out. Hidden files come
    /// too.
    @Test func gathersAFolderWithTheLinksThatStayInside() throws {
        try root.file("shared/a.txt", text: "a")
        try root.file("shared/.hidden", text: "h")
        try root.file("shared/sub/s.txt", text: "s")
        try root.file("outside/o.txt", text: "o")
        let shared = root.url.appending(path: "shared")
        let manager = FileManager.default
        func link(_ name: String, to destination: String) throws {
            try manager.createSymbolicLink(
                atPath: shared.appending(path: name).path(percentEncoded: false),
                withDestinationPath: destination)
        }
        try link("to-a.txt", to: "a.txt")
        try link("to-sub", to: "sub")
        try link("out.txt", to: "../outside/o.txt")
        try link("out-folder", to: root.url.appending(path: "outside").path(percentEncoded: false))
        try link("nowhere.txt", to: "missing.txt")
        try link("loop", to: ".")
        try link("sub/up", to: "..")

        let destination = stores.url.appending(path: "gathered")
        try Sharing.gather(shared, into: destination)

        #expect(
            try tree(destination) == [
                ".hidden", "a.txt", "sub/", "sub/s.txt", "to-a.txt", "to-sub/", "to-sub/s.txt",
            ])
        #expect(
            try String(contentsOf: destination.appending(path: "to-a.txt"), encoding: .utf8) == "a")
        #expect(try links(in: destination).isEmpty)
    }

    /// A link shared by itself is gathered as what it leads to, as Files lists
    /// it.
    @Test func gathersALinkedFolderAsWhatItLeadsTo() throws {
        try root.file("real/r.txt", text: "r")
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "alias"),
            withDestinationURL: root.url.appending(path: "real"))
        let destination = stores.url.appending(path: "alias")
        try Sharing.gather(root.url.appending(path: "alias"), into: destination)
        #expect(try tree(destination) == ["r.txt"])
    }

    /// A link to a folder holding the stores would copy the share into itself.
    @Test func refusesAnItemHoldingTheStores() throws {
        try root.file("readme")
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "around"), withDestinationURL: stores.url)
        #expect(throws: SharingError.holdsDialect("around")) {
            try Sharing.zip(
                [FilePath("around")], name: "around.zip", root: root.url, stores: stores.url)
        }
    }

    /// Among several items, a link to another of them is a copy of what it
    /// leads to; one to an item left out of the share is left out.
    @Test func takesLinksBetweenTheItemsShared() throws {
        try root.file("x/x.txt", text: "x")
        try root.file("y/y.txt", text: "y")
        try root.file("z/z.txt", text: "z")
        for (name, destination) in [("to-y.txt", "../y/y.txt"), ("to-z.txt", "../z/z.txt")] {
            try FileManager.default.createSymbolicLink(
                atPath: root.url.appending(path: "x/\(name)").path(percentEncoded: false),
                withDestinationPath: destination)
        }
        let zip = try Sharing.zip(
            [FilePath("x"), FilePath("y")], name: "Archive.zip", root: root.url,
            stores: stores.url)
        #expect(
            try ZipEntries.read(zip).map(\.name).filter { !$0.hasSuffix("/") }.sorted() == [
                "Archive/x/to-y.txt", "Archive/x/x.txt", "Archive/y/y.txt",
            ])
    }

    /// One of several items that's a link leading nowhere is left out.
    @Test func leavesOutABrokenLinkAmongSeveral() throws {
        try root.file("readme", text: "r")
        try FileManager.default.createSymbolicLink(
            atPath: root.url.appending(path: "broken").path(percentEncoded: false),
            withDestinationPath: "missing")
        let zip = try Sharing.zip(
            [FilePath("readme"), FilePath("broken")], name: "Archive.zip", root: root.url,
            stores: stores.url)
        #expect(
            try ZipEntries.read(zip).map(\.name).filter { !$0.hasSuffix("/") } == [
                "Archive/readme"
            ])
    }

    /// Two folders linking to each other: a link back into a folder being
    /// copied is left out.
    @Test func gathersLinksThatLeadInACircle() throws {
        try root.folder("shared/a")
        try root.folder("shared/b")
        let shared = root.url.appending(path: "shared")
        try FileManager.default.createSymbolicLink(
            atPath: shared.appending(path: "a/to-b").path(percentEncoded: false),
            withDestinationPath: "../b")
        try FileManager.default.createSymbolicLink(
            atPath: shared.appending(path: "b/to-a").path(percentEncoded: false),
            withDestinationPath: "../a")
        let destination = stores.url.appending(path: "gathered")
        try Sharing.gather(shared, into: destination)
        #expect(
            try tree(destination) == ["a/", "a/to-b/", "b/", "b/to-a/"])
    }

    // MARK: Files

    @Test func sendsAFileWhereItIs() throws {
        try root.file("notes/todo.txt", text: "t")
        let url = try Sharing.file(FilePath("notes/todo.txt"), root: root.url, stores: stores.url)
        #expect(url == FilePath("notes/todo.txt").url(in: root.url))
    }

    /// A link is sent as a copy of what it leads to, under its own name.
    @Test func sendsALinkedFileAsWhatItLeadsTo() throws {
        try root.file("real.txt", text: "r")
        try FileManager.default.createSymbolicLink(
            atPath: root.url.appending(path: "alias.txt").path(percentEncoded: false),
            withDestinationPath: "real.txt")
        let url = try Sharing.file(FilePath("alias.txt"), root: root.url, stores: stores.url)
        #expect(url.lastPathComponent == "alias.txt")
        #expect(url.path().hasPrefix(FilesStores.sharing(in: stores.url).path()))
        #expect(try String(contentsOf: url, encoding: .utf8) == "r")
        #expect(try links(in: url.deletingLastPathComponent()).isEmpty)
    }

    // MARK: Zips

    /// A folder is zipped with itself at the top, deflated.
    @Test func zipsAFolderUnderItsName() throws {
        try root.file("notes/todo.txt", text: String(repeating: "todo\n", count: 100))
        try root.file("notes/deep/d.md", text: "d")
        let zip = try Sharing.zip(
            [FilePath("notes")], name: "notes.zip", root: root.url, stores: stores.url)
        #expect(zip.lastPathComponent == "notes.zip")
        let entries = try ZipEntries.read(zip)
        #expect(
            entries.map(\.name).filter { !$0.hasSuffix("/") }.sorted() == [
                "notes/deep/d.md", "notes/todo.txt",
            ])
        #expect(entries.first { $0.name == "notes/todo.txt" }?.method == 8)
        // The gathered copy is gone; the zip is all that's left.
        #expect(try names(in: zip.deletingLastPathComponent()) == ["notes.zip"])
    }

    @Test func zipsSeveralInsideArchive() throws {
        try root.file("readme", text: "r")
        try root.file("notes/todo.txt", text: "t")
        try root.file("demo.dial/main.scm", text: "m")
        let zip = try Sharing.zip(
            [FilePath("readme"), FilePath("notes"), FilePath("demo.dial")], name: "Archive.zip",
            root: root.url, stores: stores.url)
        #expect(zip.lastPathComponent == "Archive.zip")
        #expect(
            try ZipEntries.read(zip).map(\.name).filter { !$0.hasSuffix("/") }.sorted() == [
                "Archive/demo.dial/main.scm", "Archive/notes/todo.txt", "Archive/readme",
            ])
    }

    /// Each share clears what earlier ones left, as does launch.
    @Test func clearsSharingAsEachShareBegins() throws {
        try root.file("a/a.txt")
        try root.file("b/b.txt")
        let first = try Sharing.zip(
            [FilePath("a")], name: "a.zip", root: root.url, stores: stores.url)
        let second = try Sharing.zip(
            [FilePath("b")], name: "b.zip", root: root.url, stores: stores.url)
        #expect(!FileManager.default.fileExists(atPath: first.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: second.path(percentEncoded: false)))
        _ = try Sharing.file(FilePath("a/a.txt"), root: root.url, stores: stores.url)
        #expect(!FileManager.default.fileExists(atPath: second.path(percentEncoded: false)))

        _ = try Sharing.zip([FilePath("a")], name: "a.zip", root: root.url, stores: stores.url)
        Sharing.clear(in: stores.url)
        let sharing = FilesStores.sharing(in: stores.url)
        #expect(!FileManager.default.fileExists(atPath: sharing.path(percentEncoded: false)))
    }

    // MARK: Helpers

    /// Every path under `folder`, folders ending in `/`, sorted.
    private func tree(_ folder: URL) throws -> [String] {
        let base = folder.resolvingSymlinksInPath().pathComponents.count
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey]))
        return try enumerator.compactMap { $0 as? URL }.map { url in
            let relative = url.resolvingSymlinksInPath().pathComponents.dropFirst(base)
                .joined(separator: "/")
            let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
            return isDirectory == true ? relative + "/" : relative
        }.sorted()
    }

    private func links(in folder: URL) throws -> [URL] {
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]))
        return try enumerator.compactMap { $0 as? URL }.filter {
            try $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
        }
    }

    private func names(in folder: URL) throws -> [String] {
        return try FileManager.default.contentsOfDirectory(
            atPath: folder.path(percentEncoded: false)
        )
        .sorted()
    }
}

/// A zip's central directory: each entry's name and compression method.
private enum ZipEntries {
    struct Entry {
        let name: String
        let method: UInt16
    }

    static func read(_ url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        // The end of central directory record, found from the end.
        let end = try #require(
            stride(from: bytes.count - 22, through: 0, by: -1).first { u32($0) == 0x0605_4b50 })
        var offset = u32(end + 16)
        var entries: [Entry] = []
        for _ in 0..<u16(end + 10) {
            #expect(u32(offset) == 0x0201_4b50)
            let nameLength = u16(offset + 28)
            let name = String(
                decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            entries.append(Entry(name: name, method: UInt16(u16(offset + 10))))
            offset += 46 + nameLength + u16(offset + 30) + u16(offset + 32)
        }
        return entries
    }
}
