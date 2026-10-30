import Foundation
import Synchronization
import Testing

@testable import Dialect

/// What the watch answers when the phone asks about Files.
struct FilesServiceTests {
    private let setup: OperationsSetup
    private let store = TestDefaults()
    private let service: FilesService

    init() throws {
        setup = try OperationsSetup()
        service = FilesService(
            root: setup.root.url, stores: setup.stores.url, defaults: store.defaults,
            sizes: setup.sizes, kinds: FileKinds(), sizesWait: .seconds(10))
    }

    private func reply(_ body: FilesRequest.Body) async -> FilesReply {
        return await service.reply(to: FilesRequest(body: body))
    }

    private func page(_ path: FilePath, offset: Int = 0, token: String? = nil) async throws
        -> ListingPage
    {
        guard case .listing(let page) = await reply(.list(path, offset: offset, token: token))
        else { throw CocoaError(.featureUnsupported) }
        return page
    }

    // MARK: Listings

    /// Pages in the order of names, losing nothing, with hidden items and
    /// without the inbox.
    @Test func pagesALargeFolder() async throws {
        let names = (0..<1500).map {
            String(format: "file %04d %@.txt", $0, String(repeating: "x", count: 120))
        }
        for name in names { try setup.root.file(name) }
        try setup.root.file(".hidden")
        try setup.root.file("Inbox/com.apple.watchconnectivity/a")

        var collected: [ListedItem] = []
        var pages = 0
        repeat {
            let page = try await page(.root, offset: collected.count)
            #expect(page.offset == collected.count)
            #expect(page.total == names.count + 1)
            collected += page.items
            pages += 1
        } while collected.count < names.count + 1
        #expect(pages > 1)
        #expect(collected.map(\.name) == ([".hidden"] + names))
    }

    @Test func aFolderKeepsItsInbox() async throws {
        try setup.root.file("notes/Inbox/a.txt")
        #expect(try await page(FilePath("notes")).items.map(\.name) == ["Inbox"])
    }

    @Test func settlesEveryKind() async throws {
        try setup.root.file("a/text", text: "plain")
        try setup.root.file("a/blob", Data([0, 1, 2]))
        try setup.root.file("a/x.scm")
        try setup.root.folder("a/s.dial")
        try setup.root.folder("a/f")
        let kinds = Dictionary(
            uniqueKeysWithValues: try await page(FilePath("a")).items.map { ($0.name, $0.kind) })
        #expect(
            kinds == [
                "text": .otherText, "blob": .binary, "x.scm": .scheme, "s.dial": .session,
                "f": .folder,
            ])
    }

    /// A token means "unchanged" only at the first page, and only while the
    /// items and the view settings stay as they were.
    @Test func answersUnchangedWithACurrentToken() async throws {
        let folder = try setup.root.folder("a")
        try setup.root.file("a/x.txt", text: "1")
        let first = try await page(FilePath("a"))
        let path = FilePath("a")

        #expect(await reply(.list(path, offset: 0, token: first.token)) == .unchanged)
        #expect(try await page(path, offset: 1, token: first.token).token == first.token)
        #expect(try await page(path, token: "other").token == first.token)

        try setup.root.file("a/x.txt", text: "12")
        let changed = try await page(path, token: first.token)
        #expect(changed.token != first.token)

        try FolderViewSettings(sort: .size).write(to: folder)
        let resorted = try await page(path, token: changed.token)
        #expect(resorted.token != changed.token)
        #expect(resorted.settings.sort == .size)
    }

    @Test func saysWhenAFolderIsMissingOrUnreadable() async throws {
        try setup.root.file("file.txt")
        try setup.root.file("Inbox/a")
        #expect(await reply(.list(FilePath("gone"), offset: 0, token: nil)) == .missing)
        #expect(await reply(.list(.inbox, offset: 0, token: nil)) == .missing)
        #expect(await reply(.info(FilePath("Inbox/a"))) == .missing)
        guard case .failed = await reply(.list(FilePath("file.txt"), offset: 0, token: nil)) else {
            Issue.record("Listing a file should fail")
            return
        }
    }

    // MARK: Totals

    /// A walk held until the test lets it go.
    private final class SlowWalker: Sendable {
        let gate = Mutex(false)
        let walks = Mutex(0)

        func walk(_ url: URL, _ skipping: String?) -> Int64? {
            walks.withLock { $0 += 1 }
            while !gate.withLock({ $0 }) { usleep(5000) }
            return FolderSizes.total(of: url, skipping: skipping)
        }
    }

    @Test func aSlowTotalStaysPendingThenArrivesFromOneWalk() async throws {
        try setup.root.file("tree/a.bin", Data(count: 10))
        let walker = SlowWalker()
        var service = service
        service.sizes = FolderSizes(walker: walker.walk)
        service.sizesWait = .milliseconds(50)
        let request = FilesRequest(body: .sizes([FilePath("tree")]))

        for _ in 0..<3 {
            #expect(await service.reply(to: request) == .sizes([:], pending: [FilePath("tree")]))
        }
        walker.gate.withLock { $0 = true }
        service.sizesWait = .seconds(10)
        #expect(await service.reply(to: request) == .sizes([FilePath("tree"): 10], pending: []))
        #expect(await service.reply(to: request) == .sizes([FilePath("tree"): 10], pending: []))
        #expect(walker.walks.withLock { $0 } == 1)
    }

    /// What's forgotten while a walk runs isn't kept from it.
    @Test func aWalkForgottenMidwayKeepsNothing() async throws {
        let tree = FilePath("tree")
        try setup.root.file("tree/a.bin", Data(count: 10))
        let walker = SlowWalker()
        let sizes = FolderSizes(walker: walker.walk)
        let root = setup.root.url
        #expect(
            await sizes.size(of: tree, root: root, modified: nil, within: .milliseconds(20)) == nil)
        await sizes.forget(containing: tree.url(in: root))
        try setup.root.file("tree/b.bin", Data(count: 5))
        walker.gate.withLock { $0 = true }
        #expect(await sizes.size(of: tree, root: root, modified: nil, within: .seconds(5)) == 15)
        #expect(walker.walks.withLock { $0 } == 2)
    }

    /// The root's total leaves out the inbox; a file or a gone path has none.
    @Test func answersTotalsForFoldersOnly() async throws {
        try setup.root.file("Inbox/big", Data(count: 1000))
        try setup.root.file("tree/a.bin", Data(count: 10))
        try setup.root.file("s.dial/main.scm", Data(count: 3))
        try setup.root.file("file.txt", Data(count: 4))
        let paths = [
            .root, FilePath("tree"), FilePath("s.dial"), FilePath("file.txt"), FilePath("gone"),
            .inbox,
        ]
        #expect(
            await reply(.sizes(paths))
                == .sizes([.root: 17, FilePath("tree"): 10, FilePath("s.dial"): 3], pending: []))
    }

    // MARK: Info

    @Test func givesInfoForAFile() async throws {
        try setup.root.file("a.md", text: "hello")
        guard case .info(let info) = await reply(.info(FilePath("a.md"))) else {
            Issue.record("No info")
            return
        }
        #expect(info.item.kind == .text)
        #expect(info.total == 5)
        #expect(info.count == nil)
        #expect(info.extended?.permissions.count == 9)
    }

    /// A folder's or session's total comes from `sizes`, which finds the walk
    /// `info` started.
    @Test(arguments: ["tree", "tree.dial"])
    func givesInfoForAFolderOrSession(name: String) async throws {
        try setup.root.file("\(name)/a.bin", Data(count: 10))
        try setup.root.file("\(name)/.b", Data(count: 1))
        guard case .info(let info) = await reply(.info(FilePath(name))) else {
            Issue.record("No info")
            return
        }
        #expect(info.item.isDirectory)
        #expect(info.count == 2)
        #expect(await reply(.sizes([FilePath(name)])) == .sizes([FilePath(name): 11], pending: []))
    }

    @Test func infoOfTheRootLeavesOutTheInbox() async throws {
        try setup.root.file("Inbox/a")
        try setup.root.file("b")
        guard case .info(let info) = await reply(.info(.root)) else {
            Issue.record("No info")
            return
        }
        #expect(info.count == 1)
    }

    // MARK: Recents and the bin

    @Test func followsTheWatchsRecentsSettings() async throws {
        for name in ["a", "b", "c", ".d"] { try setup.root.file("\(name).txt") }
        await setup.operations.recordOpen(FilePath("a.txt"))
        await setup.operations.recordOpen(FilePath("b.txt"))
        await setup.operations.recordOpen(FilePath("c.txt"))
        await setup.operations.recordOpen(FilePath(".d.txt"))
        try await setup.operations.pin(FilePath("a.txt"))
        store.defaults.set(1, forKey: RecentsSettings.showLastKey)

        guard case .recents(let pinned, let recent) = await reply(.recents) else {
            Issue.record("No recents")
            return
        }
        #expect(pinned.map(\.path) == [FilePath("a.txt")])
        #expect(recent.map(\.path) == [FilePath("c.txt")])

        store.defaults.set(true, forKey: FileSettings.showHiddenKey)
        guard case .recents(_, let shown) = await reply(.recents) else {
            Issue.record("No recents")
            return
        }
        #expect(shown.map(\.path) == [FilePath(".d.txt")])
    }

    @Test func pagesTheBinNewestFirst() async throws {
        try setup.root.file("notes/a.md")
        try setup.root.file("b.scm")
        let earlier = Date(timeIntervalSince1970: 1_000_000_000)
        _ = try await setup.operations.delete([FilePath("notes/a.md")], now: earlier)
        _ = try await setup.operations.delete([FilePath("b.scm")], now: earlier + 60)

        guard case .bin(let page) = await reply(.bin(offset: 0, token: nil)) else {
            Issue.record("No bin")
            return
        }
        #expect(page.total == 2)
        #expect(page.items.map(\.name) == ["b.scm", "a.md"])
        #expect(page.items.map(\.kind) == [.scheme, .text])
        #expect(page.items[1].original == FilePath("notes/a.md"))
        #expect(page.items[1].deleted == earlier)
        #expect(await reply(.bin(offset: 0, token: page.token)) == .unchanged)
    }

    /// Opening a pipe would wait for a writer, and the phone with it.
    @Test func aPipeInTheBinIsNeverOpened() async throws {
        let pipe = setup.root.url.appending(path: "pipe")
        #expect(mkfifo(pipe.path(percentEncoded: false), 0o600) == 0)
        _ = try await setup.operations.delete([FilePath("pipe")])
        guard case .bin(let page) = await reply(.bin(offset: 0, token: nil)) else {
            Issue.record("No bin")
            return
        }
        #expect(page.items.map(\.kind) == [.binary])
    }

    // MARK: Whatever arrives

    private func decoded(_ data: Data) throws -> FilesReply {
        return try FilesCoding.decode(FilesReply.self, from: data)
    }

    @Test func answersAnotherFormat() async throws {
        let data = Data(#"{"format":99,"body":{"something":{}}}"#.utf8)
        #expect(try decoded(await service.replyData(to: data)) == .otherFormat(1))
    }

    @Test func answersUndecodableData() async throws {
        guard case .failed = try decoded(await service.replyData(to: Data("nope".utf8))) else {
            Issue.record("Should fail")
            return
        }
        let reachingOut = Data(#"{"format":1,"body":{"info":{"_0":["..","secret"]}}}"#.utf8)
        guard case .failed = try decoded(await service.replyData(to: reachingOut)) else {
            Issue.record("Should fail")
            return
        }
    }

    /// Info on an item whose extended attributes won't fit a message.
    @Test func answersWhatsTooLargeToSend() async throws {
        let url = try setup.root.file("a.txt")
        for index in 0..<1500 {
            try ExtendedAttributes.set(
                "user." + String(repeating: "x", count: 100) + "\(index)", Data([1]), at: url)
        }
        let request = try FilesCoding.encode(FilesRequest(body: .info(FilePath("a.txt"))))
        let data = await service.replyData(to: request)
        #expect(data.count <= FilesPaging.messageLimit)
        guard case .failed = try decoded(data) else {
            Issue.record("Should fail")
            return
        }
    }

    // MARK: By user info

    @Test func answersByUserInfoUntilARequestIsOld() async throws {
        try setup.root.file("a.txt")
        let data = try FilesCoding.encode(FilesRequest(body: .list(.root, offset: 0, token: nil)))
        let now = Date()
        let request = try #require(
            FilesUserInfo(
                request: FilesUserInfo(id: "A", data: data, sent: now - 9).propertyList))

        let answer = try #require(await service.answer(request, now: now))
        let received = try #require(FilesUserInfo(answer: answer.propertyList))
        #expect(received.id == "A")
        guard case .listing(let page) = try decoded(received.data) else {
            Issue.record("No listing")
            return
        }
        #expect(page.items.map(\.name) == ["a.txt"])

        let old = FilesUserInfo(id: "B", data: data, sent: now - 11)
        #expect(await service.answer(old, now: now) == nil)
    }

    // MARK: Nothing changes

    /// Every path, its contents and its dates, in Files and its stores.
    private func everything() throws -> [String: String] {
        var found: [String: String] = [:]
        for base in [setup.root.url, setup.stores.url] {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
            let walker = try #require(
                FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys))
            for case let url as URL in walker {
                let values = try url.resourceValues(forKeys: Set(keys))
                let contents = values.isRegularFile == true ? try Data(contentsOf: url) : Data()
                found[url.path] =
                    "\(values.contentModificationDate ?? .distantPast) \(contents.base64EncodedString())"
            }
        }
        return found
    }

    @Test func changesNothing() async throws {
        let folder = try setup.root.folder("notes")
        try FolderViewSettings(sort: .size).write(to: folder)
        try setup.root.file("notes/plain", text: "text")
        try setup.root.file("notes/a.md", text: "text")
        try setup.root.file("gone-soon.md", text: "text")
        try setup.root.file("Inbox/x")
        _ = try await setup.operations.delete([FilePath("gone-soon.md")])
        await setup.operations.recordOpen(FilePath("notes/a.md"))
        try await setup.operations.copy([FilePath("notes/a.md")])
        let before = try everything()

        let requests: [FilesRequest.Body] = [
            .list(.root, offset: 0, token: nil), .list(FilePath("notes"), offset: 0, token: nil),
            .list(FilePath("gone"), offset: 0, token: nil), .sizes([.root, FilePath("notes")]),
            .info(FilePath("notes")), .info(FilePath("notes/a.md")), .recents,
            .bin(offset: 0, token: nil),
        ]
        for body in requests { _ = await reply(body) }
        #expect(try everything() == before)
    }
}
