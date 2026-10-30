import Foundation
import Testing

@testable import Dialect

/// What the phone asks of the watch's Files and what it hears back: each
/// survives the trip, and each fits a message.
struct FilesMessagesTests {
    private let noon = Date(timeIntervalSince1970: 1_790_000_000.25)

    private func trip<T: Codable>(_ value: T) throws -> T {
        return try FilesCoding.decode(T.self, from: FilesCoding.encode(value))
    }

    private func file(_ path: String) -> FileItem {
        return FileItem(
            path: FilePath(path), kind: .text, isDirectory: false, size: 12, created: noon,
            modified: noon + 60, isReadOnly: true)
    }

    private func listed(_ name: String) -> ListedItem {
        return ListedItem(
            name: name, kind: .scheme, size: 1000, created: noon, modified: noon, isReadOnly: false)
    }

    // MARK: Round trips

    @Test(arguments: [
        FilesRequest.Body.list(FilePath("notes/a"), offset: 40, token: "abc"),
        .list(.root, offset: 0, token: nil),
        .sizes([FilePath("a"), FilePath("b/c")]),
        .info(FilePath("notes.md")),
        .recents,
        .bin(offset: 3, token: "def"),
    ])
    func requestsRoundTrip(body: FilesRequest.Body) throws {
        let request = try trip(FilesRequest(body: body))
        #expect(request.format == FilesRequest.currentFormat)
        #expect(request.body == body)
    }

    @Test func repliesRoundTrip() throws {
        let settings = FolderViewSettings(sort: .size, ascending: false, grouping: .kind)
        let extended = ExtendedInfo(
            permissions: "rw-r--r--", access: ["Owner: Read"], owner: "mobile", group: "mobile",
            attributes: [ExtendedAttribute(name: "user.x", size: 3)])
        let replies: [FilesReply] = [
            .listing(
                ListingPage(
                    items: [listed("a.scm")], settings: settings, token: "t", total: 9, offset: 4)),
            .bin(
                BinPage(
                    items: [
                        ListedBinItem(
                            id: UUID(), name: "a.md", original: FilePath("notes/a.md"),
                            deleted: noon, kind: .text)
                    ], token: "t", total: 1, offset: 0)),
            .unchanged,
            .sizes([FilePath("a"): 10, .root: 3], pending: [FilePath("b")]),
            .info(ItemInfo(item: file("a.md"), total: 40, count: 2, extended: extended)),
            .info(ItemInfo(item: file("a.md"), total: nil, count: nil, extended: nil)),
            .recents(pinned: [file("p.md")], recent: [file("n/r.md")]),
            .missing,
            .failed("No"),
            .otherFormat(2),
        ]
        for reply in replies { #expect(try trip(reply) == reply) }
    }

    @Test func aDamagedPathDoesntDecode() {
        let data = Data(#"{"format":1,"body":{"info":{"_0":[".."]}}}"#.utf8)
        #expect(throws: (any Error).self) {
            try FilesCoding.decode(FilesRequest.self, from: data)
        }
    }

    // MARK: Kinds

    @Test(arguments: FileKind.allCases)
    func kindsRoundTrip(kind: FileKind) throws {
        #expect(try trip(kind) == kind)
    }

    @Test func anUnknownKindReadsAsBinary() throws {
        let kind = try FilesCoding.decode(FileKind.self, from: Data(#""hologram""#.utf8))
        #expect(kind == .binary)
    }

    /// Folders and sessions are directories, in both forms an item travels in.
    @Test(arguments: FileKind.allCases)
    func isDirectoryFollowsTheKind(kind: FileKind) throws {
        let directory = kind == .folder || kind == .session
        let item = ListedItem(
            name: "x", kind: kind, size: nil, created: nil, modified: nil, isReadOnly: false)
        #expect(try trip(item).item(in: FilePath("a")).isDirectory == directory)
        #expect(item.item(in: FilePath("a")).path == FilePath("a/x"))

        let whole = FileItem(
            path: FilePath("a/x"), kind: kind, isDirectory: directory, size: nil, created: nil,
            modified: nil, isReadOnly: false)
        #expect(try trip(whole) == whole)
    }

    /// A listed item keeps what its row and Info show.
    @Test func aListedItemKeepsItsFields() throws {
        let item = file("notes/a.md")
        #expect(ListedItem(item).item(in: FilePath("notes")) == item)
        #expect(try trip(ListedItem(item)) == ListedItem(item))
    }

    // MARK: Pages

    /// All the items, page by page, each page a whole reply.
    private func pages(
        _ items: [ListedItem], reply: (Int, [ListedItem]) -> FilesReply
    ) throws -> [ListedItem] {
        let lengths = try items.map { try FilesCoding.encode($0).count }
        var collected: [ListedItem] = []
        while collected.count < items.count {
            let range = FilesPaging.page(of: lengths, from: collected.count)
            let page = Array(items[range])
            let size = try FilesCoding.encode(reply(items.count, page)).count
            #expect(size <= FilesPaging.messageLimit)
            collected += page
        }
        return collected
    }

    /// Ordinary names, the longest there can be, and names JSON escapes.
    @Test(arguments: [
        "note ", String(repeating: "x", count: 250), String(repeating: "\"", count: 120),
    ])
    func pagesStayWithinAMessage(stem: String) throws {
        let items = (0..<2000).map { listed("\(stem)\($0)") }
        let settings = FolderViewSettings(sort: .modified, ascending: false, grouping: .modified)
        let listing = try pages(items) { total, page in
            .listing(
                ListingPage(
                    items: page, settings: settings, token: String(repeating: "t", count: 64),
                    total: total, offset: 0))
        }
        #expect(listing == items)
    }

    @Test func binPagesStayWithinAMessage() throws {
        let long = String(repeating: "\"", count: 120)
        let items = (0..<1000).map { index in
            ListedBinItem(
                id: UUID(), name: "\(long)\(index)", original: FilePath("a/\(long)\(index)"),
                deleted: noon, kind: .binary)
        }
        let lengths = try items.map { try FilesCoding.encode($0).count }
        var collected: [ListedBinItem] = []
        while collected.count < items.count {
            let page = Array(items[FilesPaging.page(of: lengths, from: collected.count)])
            let reply = FilesReply.bin(
                BinPage(
                    items: page, token: String(repeating: "t", count: 64), total: items.count,
                    offset: collected.count))
            #expect(try FilesCoding.encode(reply).count <= FilesPaging.messageLimit)
            collected += page
        }
        #expect(collected == items)
    }

    @Test func aPageAlwaysHoldsAnItem() {
        #expect(FilesPaging.page(of: [100, 100], from: 0, budget: 10) == 0..<1)
        #expect(FilesPaging.page(of: [100, 100], from: 1, budget: 10) == 1..<2)
        #expect(FilesPaging.page(of: [100, 100], from: 2, budget: 10) == 2..<2)
        #expect(FilesPaging.page(of: [4, 4, 4], from: 0, budget: 10) == 0..<2)
    }

    @Test func anOffsetOutsideTheListingGivesNoItems() {
        #expect(FilesPaging.page(of: [4, 4], from: -1) == 2..<2)
        #expect(FilesPaging.page(of: [4, 4], from: 3) == 2..<2)
        #expect(FilesPaging.page(of: [], from: 0) == 0..<0)
    }

    // MARK: The largest of the others

    /// A path as deep as the system allows.
    private func deepPath(_ index: Int, name: String = "folder") -> FilePath {
        let components = (0..<(1000 / (name.utf8.count + 1))).map { _ in name }
        return FilePath(components: components + ["\(index)"])
    }

    @Test(arguments: ["folder", "\"\"\"\"\"\""])
    func sizesFitBothWays(name: String) throws {
        let paths = (0..<100).map { deepPath($0, name: name) }
        let batches = FilesPaging.batches(of: paths)
        #expect(Array(batches.joined()) == paths)
        for batch in batches {
            #expect(batch.count <= FilesPaging.sizesLimit)
            let request = FilesRequest(body: .sizes(batch))
            #expect(try FilesCoding.encode(request).count <= FilesPaging.messageLimit)

            let answered = FilesReply.sizes(
                Dictionary(uniqueKeysWithValues: batch.map { ($0, Int64.max) }), pending: [])
            #expect(try FilesCoding.encode(answered).count <= FilesPaging.messageLimit)
            let pending = FilesReply.sizes([:], pending: batch)
            #expect(try FilesCoding.encode(pending).count <= FilesPaging.messageLimit)
        }
    }

    @Test func recentsFit() throws {
        let items = (0..<(Recents.capacity + Recents.pinLimit)).map { index in
            FileItem(
                path: deepPath(index), kind: .scheme, isDirectory: false, size: .max, created: noon,
                modified: noon, isReadOnly: false)
        }
        let reply = FilesReply.recents(pinned: Array(items[..<3]), recent: Array(items[3...]))
        #expect(try FilesCoding.encode(reply).count <= FilesPaging.messageLimit)
    }
}
