import Foundation
import Synchronization
import Testing

@testable import DialectCompanion

/// Something a fake watch waits on, for a test to hold an answer back.
private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

/// What the fake watch says next, changed by tests.
private final class Script: Sendable {
    let handler = Mutex<FakeFilesConnection.Handler>({ _ in .missing })

    func set(_ handler: @escaping FakeFilesConnection.Handler) {
        self.handler.withLock { $0 = handler }
    }
}

private let seenDate = Date(timeIntervalSince1970: 1_790_000_000)

private func item(_ name: String, kind: FileKind = .text) -> ListedItem {
    return ListedItem(
        name: name, kind: kind, size: 3, created: nil, modified: seenDate, isReadOnly: false)
}

/// A page of a listing, by default the whole of it.
private func listing(
    _ items: [ListedItem], settings: FolderViewSettings = FolderViewSettings(), token: String = "T",
    total: Int? = nil, offset: Int = 0
) -> FilesReply {
    return .listing(
        ListingPage(
            items: items, settings: settings, token: token, total: total ?? items.count,
            offset: offset))
}

/// Counts up from 1, from any task.
private final class Counter: Sendable {
    private let count = Mutex(0)

    func next() -> Int {
        return count.withLock {
            $0 += 1
            return $0
        }
    }

    var value: Int { count.withLock { $0 } }
}

@MainActor
private func waitUntil(
    _ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async {
    for _ in 0..<2000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Never happened", sourceLocation: sourceLocation)
}

@MainActor
struct BrowsingTests {
    private let directory = CacheDirectory()
    private let script = Script()
    private let connection: FakeFilesConnection
    private let files: WatchFiles
    private let notes = FilePath("notes")
    private let seen = seenDate

    init() async {
        let script = script
        connection = FakeFilesConnection { body in
            let handler = script.handler.withLock { $0 }
            return try await handler(body)
        }
        files = WatchFiles(
            connection: connection, connectAfter: .milliseconds(60),
            disconnectAfter: .milliseconds(120), pendingRetry: .milliseconds(20))
        follow(reachable: true)
        await files.cacheSettled()
    }

    private func follow(
        status: LinkStatus? = .connected, reachable: Bool, epoch: String? = "A",
        display: FilesDisplay = FilesDisplay()
    ) {
        files.follow(
            FilesLinkState(
                status: status, isReachable: reachable, epoch: epoch, directory: directory.url,
                display: display))
    }

    /// Stores a folder the watch showed earlier.
    private func cache(_ names: [String], token: String = "OLD") async {
        await files.cache.store(
            CachedFolder(
                items: names.map { item($0) }, settings: FolderViewSettings(), token: token,
                seen: seen), at: notes, epoch: "A")
    }

    private func names(_ model: FolderModel) -> [String] {
        return model.items.map(\.name)
    }

    // MARK: Cache, then live

    @Test func showsTheCacheBeforeTheReplyThenLive() async {
        await cache(["old.txt"])
        let gate = Gate()
        let new = item("new.txt")
        script.set { _ in
            await gate.wait()
            return listing([new], settings: FolderViewSettings(sort: .size))
        }
        let model = FolderModel(path: notes, files: files)
        let refresh = Task { await model.refresh() }
        await waitUntil { names(model) == ["old.txt"] }
        #expect(model.state == .loading)

        await gate.open()
        await refresh.value
        #expect(names(model) == ["new.txt"])
        #expect(model.state == .live)
        #expect(model.settings.sort == .size)
        #expect(model.items[0].path == FilePath("notes/new.txt"))
    }

    @Test func askingWithTheCachedTokenKeepsTheRowsWhenUnchanged() async throws {
        await cache(["old.txt"])
        script.set { _ in .unchanged }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(names(model) == ["old.txt"])
        #expect(model.state == .live)
        #expect(connection.requests == [.list(notes, offset: 0, token: "OLD")])

        // "Last seen" moves on.
        let stored = await files.cache.folder(notes)
        #expect((stored?.seen ?? seen) > seen)
    }

    @Test func pagesFillIn() async {
        let first = Gate()
        let second = Gate()
        let a = item("a")
        let b = item("b")
        script.set { body in
            guard case .list(_, let offset, let token) = body else { return .missing }
            if offset == 0 {
                #expect(token == nil)
                await first.wait()
                return listing([a], total: 2)
            }
            #expect(token == "T")
            await second.wait()
            return listing([b], total: 2, offset: 1)
        }
        let model = FolderModel(path: notes, files: files)
        let refresh = Task { await model.refresh() }
        await first.open()
        await waitUntil { names(model) == ["a"] }
        #expect(model.state == .loading)
        await second.open()
        await refresh.value
        #expect(names(model) == ["a", "b"])
        #expect(model.state == .live)
    }

    @Test func aListingChangingBetweenPagesStartsOverOnce() async {
        let calls = Counter()
        let (a, b, c) = (item("a"), item("b"), item("c"))
        script.set { _ in
            let call = calls.next()
            switch call {
            case 1:
                return listing([a], token: "1", total: 2)
            case 2:
                return listing([c], token: "2", total: 2, offset: 1)
            case 3:
                return listing([b], token: "2", total: 2)
            default:
                return listing([c], token: "2", total: 2, offset: 1)
            }
        }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(names(model) == ["b", "c"])
        #expect(model.state == .live)
    }

    @Test func aSecondChangeKeepsTheRowsAndReadsAsAFailure() async {
        await cache(["old.txt"])
        let calls = Counter()
        let a = item("a")
        script.set { _ in
            let call = calls.next()
            return listing([a], token: "\(call)", total: 2)
        }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(names(model) == ["old.txt"])
        #expect(model.state == .cached(seen))
        #expect(model.lastRequestFailed)
    }

    @Test func aFailureMidPagesNeitherTruncatesNorOverwrites() async throws {
        await cache(["old.txt", "older.txt"])
        let a = item("a")
        script.set { body in
            guard case .list(_, 0, _) = body else { throw CocoaError(.fileLocking) }
            return listing([a], total: 2)
        }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(names(model) == ["old.txt", "older.txt"])
        #expect(model.state == .cached(seen))
        #expect(await files.cache.folder(notes)?.items.map(\.name) == ["old.txt", "older.txt"])
    }

    /// A page's view settings wait for the whole listing.
    @Test func aFailureMidPagesKeepsTheViewSettings() async {
        await cache(["old.txt", "older.txt"])
        let a = item("a")
        script.set { body in
            guard case .list(_, 0, _) = body else { throw CocoaError(.fileLocking) }
            return listing([a], settings: FolderViewSettings(sort: .size), total: 2)
        }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(model.settings.sort == .name)
    }

    @Test func aLateReplyFromAnOlderRefreshIsIgnored() async {
        let gate = Gate()
        let calls = Counter()
        let (old, new) = (item("old"), item("new"))
        script.set { _ in
            let call = calls.next()
            if call == 1 {
                await gate.wait()
                return listing([old], token: "1")
            }
            return listing([new], token: "2")
        }
        let model = FolderModel(path: notes, files: files)
        let first = Task { await model.refresh() }
        await waitUntil { connection.requests.count == 1 }
        await model.refresh()
        #expect(names(model) == ["new"])
        await gate.open()
        await first.value
        #expect(names(model) == ["new"])
    }

    @Test func aFailureWhileConnectedKeepsTheCacheWithItsDate() async {
        await cache(["old.txt"])
        script.set { _ in throw FilesConnectionError.timedOut }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(names(model) == ["old.txt"])
        #expect(model.state == .cached(seen))
    }

    /// A part of a folder would read as all of it.
    @Test func aFailureMidPagesWithNoRowsShowsNone() async {
        let a = item("a")
        script.set { body in
            guard case .list(_, 0, _) = body else { throw CocoaError(.fileLocking) }
            return listing([a], total: 2)
        }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(model.items.isEmpty)
        guard case .failed = model.state else {
            Issue.record("Should say it failed, not \(model.state)")
            return
        }
    }

    @Test func aFailureWithNoCacheSaysWhy() async {
        script.set { _ in .failed("It broke") }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(model.state == .failed("It broke"))
    }

    // MARK: Away

    /// An answer by user info is as good as live, until the disconnect wait
    /// passes without a connection.
    @Test func awayAnAnswerIsLiveThenCached() async {
        follow(status: .away, reachable: false)
        await waitUntil { !files.isConnected }
        let a = item("a")
        script.set { _ in
            listing([a])
        }
        let model = FolderModel(path: notes, files: files)
        let reading = Task { await files.refresh(model) }
        await waitUntil { model.state == .live }
        await reading.value
        guard case .cached = model.state else {
            Issue.record("Should read as cached, not \(model.state)")
            return
        }
    }

    /// Reachability returning, with the answer in before the connection
    /// settles.
    @Test func anAnswerBeforeTheConnectionStaysLive() async {
        follow(status: .away, reachable: false)
        await waitUntil { !files.isConnected }
        let a = item("a")
        script.set { _ in
            listing([a])
        }
        let model = FolderModel(path: notes, files: files)
        follow(reachable: true)
        await files.refresh(model)
        #expect(files.isConnected)
        #expect(model.state == .live)
    }

    @Test func awayWithoutAnAnswerShowsTheCacheOrSaysNeverSeen() async {
        follow(status: .away, reachable: false)
        script.set { _ in throw FilesConnectionError.noAnswer }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(model.state == .neverSeen)

        await cache(["old.txt"])
        let seenBefore = FolderModel(path: notes, files: files)
        await seenBefore.refresh()
        #expect(seenBefore.state == .cached(seen))
        #expect(names(seenBefore) == ["old.txt"])
    }

    @Test func missingDropsTheCachedFolder() async {
        await cache(["old.txt"])
        script.set { _ in .missing }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(model.items.isEmpty)
        #expect(model.state == .missing)
        #expect(await files.cache.folder(notes) == nil)
    }

    @Test(arguments: [
        LinkStatus.unpaired, .notInstalled, .noSnapshot, .otherFormat(watchIsNewer: true),
    ])
    func statusesThatHideFilesAskNothing(status: LinkStatus) async {
        follow(status: status, reachable: false)
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(model.state == .unavailable)
        #expect(connection.requests.isEmpty)
    }

    @Test func beforeTheSessionIsActiveItShowsTheCacheWithNoMessage() async {
        await cache(["old.txt"])
        follow(status: nil, reachable: false)
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(names(model) == ["old.txt"])
        #expect(model.state == .loading)
        #expect(connection.requests.isEmpty)
    }

    /// The watch answers in another format.
    @Test func anotherFormatReadsAsUnavailable() async {
        script.set { _ in .otherFormat(2) }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(model.state == .unavailable)
    }

    // MARK: Connected, debounced

    @Test func aShortBlipChangesNothing() async throws {
        follow(reachable: false)
        await waitUntil { !files.isConnected }
        follow(reachable: true)
        follow(reachable: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!files.isConnected)
    }

    @Test func becomesConnectedAfterTheDelayAndStaysThroughAShortDrop() async throws {
        follow(reachable: false)
        await waitUntil { !files.isConnected }
        follow(reachable: true)
        #expect(!files.isConnected)
        await waitUntil { files.isConnected }

        follow(reachable: false)
        try await Task.sleep(for: .milliseconds(40))
        follow(reachable: true)
        try await Task.sleep(for: .milliseconds(160))
        #expect(files.isConnected)

        follow(reachable: false)
        #expect(files.isConnected)
        await waitUntil { !files.isConnected }
    }

    @Test func anOpenScreenGoesFromLiveToCachedWhenTheConnectionEnds() async {
        let a = item("a")
        script.set { _ in
            listing([a])
        }
        await waitUntil { files.isConnected }
        let model = FolderModel(path: notes, files: files)
        files.showing(model)
        await model.refresh()
        #expect(model.state == .live)

        follow(status: .away, reachable: false)
        await waitUntil { !files.isConnected }
        guard case .cached = model.state else {
            Issue.record("Should read as cached, not \(model.state)")
            return
        }
    }

    @Test func becomingConnectedRefreshesTheScreenOnTop() async {
        follow(status: .away, reachable: false)
        await waitUntil { !files.isConnected }
        script.set { _ in throw FilesConnectionError.noAnswer }
        let model = FolderModel(path: notes, files: files)
        files.showing(model)
        await model.refresh()
        #expect(model.state == .neverSeen)

        let a = item("a")
        script.set { _ in
            listing([a])
        }
        follow(reachable: true)
        await waitUntil { model.state == .live }
    }

    /// It needn't wait for the debounce, as what failed may have been a blip.
    @Test func reachabilityReturningRefreshesAfterAFailedRequest() async {
        await waitUntil { files.isConnected }
        script.set { _ in throw FilesConnectionError.timedOut }
        let model = FolderModel(path: notes, files: files)
        files.showing(model)
        await model.refresh()
        #expect(model.lastRequestFailed)

        let a = item("a")
        script.set { _ in
            listing([a])
        }
        follow(reachable: false)
        follow(reachable: true)
        await waitUntil { model.state == .live }
        #expect(!model.lastRequestFailed)
    }

    @Test func aRefreshAfterSuccessStaysQuietWhenReachabilityReturns() async throws {
        await waitUntil { files.isConnected }
        let a = item("a")
        script.set { _ in
            listing([a])
        }
        let model = FolderModel(path: notes, files: files)
        files.showing(model)
        await model.refresh()
        let asked = connection.requests.count
        follow(reachable: false)
        follow(reachable: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(connection.requests.count == asked)
    }

    /// Reachability returning after a failure asks once, without the debounce's
    /// read as well.
    @Test func reconnectingAfterAFailureReadsOnce() async throws {
        follow(status: .away, reachable: false)
        await waitUntil { !files.isConnected }
        script.set { _ in throw FilesConnectionError.noAnswer }
        let model = FolderModel(path: notes, files: files)
        files.showing(model)
        await model.refresh()
        let asked = connection.requests.count

        let a = item("a")
        script.set { _ in listing([a]) }
        follow(reachable: true)
        await waitUntil { files.isConnected }
        try await Task.sleep(for: .milliseconds(50))
        #expect(connection.requests.count == asked + 1)
        #expect(model.state == .live)
    }

    /// A screen left stops what it was reading.
    @Test func leavingStopsTheRead() async {
        let gate = Gate()
        let a = item("a")
        script.set { _ in
            await gate.wait()
            return listing([a])
        }
        let model = FolderModel(path: notes, files: files)
        let refresh = Task { await model.refresh() }
        await waitUntil { !connection.requests.isEmpty }
        model.leave()
        await gate.open()
        await refresh.value
        #expect(model.items.isEmpty)
    }

    /// The first status after activation may hide Files.
    @Test func aScreenWaitingForTheSessionHearsTheStatus() async {
        follow(status: nil, reachable: false)
        let model = FolderModel(path: notes, files: files)
        files.showing(model)
        await model.refresh()
        #expect(model.state == .loading)

        follow(status: .unpaired, reachable: false)
        await waitUntil { model.state == .unavailable }
    }

    @Test func aStatusThatHidesFilesHidesTheRows() async {
        let a = item("a")
        script.set { _ in listing([a]) }
        let model = FolderModel(path: notes, files: files)
        files.showing(model)
        await model.refresh()
        #expect(!model.sections(now: seen).isEmpty)

        follow(status: .notInstalled, reachable: false)
        await waitUntil { model.state == .unavailable }
        #expect(model.sections(now: seen).isEmpty)
    }

    /// A reinstalled Dialect's files aren't the ones showing, on top or further
    /// back, even when the status hid Files in between.
    @Test(arguments: [false, true])
    func anotherEpochClearsTheScreensAndReadsAgain(throughHiding: Bool) async {
        let a = item("a")
        script.set { _ in listing([a]) }
        let below = FolderModel(path: FilePath("other"), files: files)
        files.showing(below)
        await below.refresh()
        let model = FolderModel(path: notes, files: files)
        files.showing(model)
        await model.refresh()
        #expect(!below.items.isEmpty)

        let b = item("b")
        script.set { _ in listing([b]) }
        if throughHiding { follow(status: .notInstalled, reachable: true, epoch: nil) }
        follow(reachable: true, epoch: "B")
        #expect(below.items.isEmpty)
        await waitUntil { names(model) == ["b"] }
    }

    @Test func aReadAcrossAnotherEpochIsDropped() async {
        let gate = Gate()
        let calls = Counter()
        let (a, b) = (item("a"), item("b"))
        script.set { _ in
            guard calls.next() > 1 else {
                await gate.wait()
                return listing([a])
            }
            return listing([b])
        }
        let model = FolderModel(path: notes, files: files)
        files.showing(model)
        let first = Task { await model.refresh() }
        await waitUntil { calls.value == 1 }

        follow(reachable: true, epoch: "B")
        await waitUntil { names(model) == ["b"] }
        await gate.open()
        await first.value
        #expect(names(model) == ["b"])
    }

    @Test func comingBackToTheAppReadsAgain() async {
        let a = item("a")
        script.set { _ in listing([a]) }
        let model = FolderModel(path: notes, files: files)
        files.showing(model)
        await model.refresh()
        let asked = connection.requests.count
        files.becameActive()
        await waitUntil { connection.requests.count == asked + 1 }
    }

    // MARK: What shows

    @Test func hiddenItemsFilterByTheSetting() async {
        let (a, hidden) = (item("a"), item(".hidden"))
        script.set { _ in
            listing([hidden, a])
        }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(model.sections(now: seen).flatMap(\.items).map(\.name) == ["a"])

        var display = FilesDisplay()
        display.showHidden = true
        follow(reachable: true, display: display)
        #expect(model.sections(now: seen).flatMap(\.items).map(\.name) == [".hidden", "a"])
    }

    /// Sizes aren't asked for unless Details is on or the sort needs them.
    @Test func sizesAreAskedForOnlyWhenTheyShow() async {
        let folder = item("sub", kind: .folder)
        script.set { body in
            if case .sizes = body { return .sizes([:], pending: []) }
            return listing([folder])
        }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(connection.requests.count == 1)

        var display = FilesDisplay()
        display.showDetails = true
        follow(reachable: true, display: display)
        script.set { body in
            if case .sizes = body { return .sizes([FilePath("notes/sub"): 7], pending: []) }
            return .unchanged
        }
        await model.refresh()
        #expect(connection.requests.last == .sizes([FilePath("notes/sub")]))
        #expect(model.sizes == [FilePath("notes/sub"): 7])
    }

    @Test func sortingBySizeAsksToo() async {
        let folder = item("sub", kind: .folder)
        script.set { body in
            if case .sizes = body { return .sizes([FilePath("notes/sub"): 7], pending: []) }
            return listing([folder], settings: FolderViewSettings(sort: .size))
        }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(model.sizes == [FilePath("notes/sub"): 7])
    }

    @Test func pendingSizesAreAskedForAgainWhileConnected() async {
        var display = FilesDisplay()
        display.showDetails = true
        follow(reachable: true, display: display)
        await waitUntil { files.isConnected }
        let folder = item("sub", kind: .folder)
        let path = FilePath("notes/sub")
        let asks = Counter()
        script.set { body in
            guard case .sizes = body else {
                return listing([folder])
            }
            let ask = asks.next()
            return ask < 3 ? .sizes([:], pending: [path]) : .sizes([path: 7], pending: [])
        }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(model.sizes == [path: 7])
        #expect(asks.value == 3)
    }

    @Test func pendingSizesWaitWhenNotConnected() async {
        var display = FilesDisplay()
        display.showDetails = true
        follow(status: .away, reachable: false, display: display)
        await waitUntil { !files.isConnected }
        let folder = item("sub", kind: .folder)
        let path = FilePath("notes/sub")
        let asks = Counter()
        script.set { body in
            guard case .sizes = body else {
                return listing([folder])
            }
            _ = asks.next()
            return .sizes([:], pending: [path])
        }
        let model = FolderModel(path: notes, files: files)
        await model.refresh()
        #expect(asks.value == 1)
    }

    // MARK: Recents and the Trash

    private func file(_ path: String) -> FileItem {
        return FileItem(
            path: FilePath(path), kind: .text, isDirectory: false, size: 1, created: nil,
            modified: nil, isReadOnly: false)
    }

    @Test func recentsGoLiveAndAreKept() async {
        let (pin, other) = (file("p.md"), file("n/r.md"))
        script.set { _ in .recents(pinned: [pin], recent: [other]) }
        let model = RecentsModel(files: files)
        await model.refresh()
        #expect(model.pinned == [pin])
        #expect(model.recent == [other])
        #expect(model.state == .live)

        follow(status: .away, reachable: false)
        script.set { _ in throw FilesConnectionError.noAnswer }
        let later = RecentsModel(files: files)
        await later.refresh()
        #expect(later.recent == [other])
        guard case .cached = later.state else {
            Issue.record("Should read as cached")
            return
        }
    }

    @Test func recentsNeverSeenSaySo() async {
        follow(status: .away, reachable: false)
        script.set { _ in throw FilesConnectionError.noAnswer }
        let model = RecentsModel(files: files)
        await model.refresh()
        #expect(model.state == .neverSeen)
    }

    @Test func theBinPagesAndIsKept() async {
        let a = ListedBinItem(
            id: UUID(), name: "a", original: FilePath("a"), deleted: seen, kind: .text)
        let b = ListedBinItem(
            id: UUID(), name: "b", original: FilePath("b"), deleted: seen, kind: .text)
        script.set { body in
            guard case .bin(let offset, _) = body else { return .missing }
            return .bin(
                BinPage(items: offset == 0 ? [a] : [b], token: "T", total: 2, offset: offset))
        }
        let model = BinModel(files: files)
        await model.refresh()
        #expect(model.items == [a, b])
        #expect(model.state == .live)

        script.set { _ in .unchanged }
        let again = BinModel(files: files)
        await again.refresh()
        #expect(again.items == [a, b])
        #expect(again.state == .live)
        #expect(connection.requests.last == .bin(offset: 0, token: "T"))
    }
}

/// An item's Info on the phone.
@MainActor
struct ItemInfoModelTests {
    private let directory = CacheDirectory()

    private func model(
        _ item: FileItem, reachable: Bool = true, handler: @escaping FakeFilesConnection.Handler
    ) async -> ItemInfoModel {
        let files = WatchFiles(
            connection: FakeFilesConnection(handler: handler), connectAfter: .zero,
            pendingRetry: .milliseconds(5))
        files.follow(
            FilesLinkState(
                status: reachable ? .connected : .away, isReachable: reachable, epoch: "A",
                directory: directory.url))
        await files.cacheSettled()
        if reachable { await waitUntil { files.isConnected } }
        return ItemInfoModel(item: item, files: files)
    }

    private func folder(_ path: FilePath) -> FileItem {
        return FileItem(
            path: path, kind: .folder, isDirectory: true, size: nil, created: nil, modified: nil,
            isReadOnly: false)
    }

    private let extended = ExtendedInfo(
        permissions: "rwxr-xr-x", access: [], owner: "o", group: "g", attributes: [])

    /// The total arrives from `sizes` when `info` hasn't got it yet.
    @Test func fillsInAndAsksForAPendingTotal() async {
        let path = FilePath("notes")
        let item = folder(path)
        let extended = extended
        let asks = Counter()
        let model = await model(item) { body in
            switch body {
            case .info:
                return .info(ItemInfo(item: item, total: nil, count: 3, extended: extended))
            default:
                let ask = asks.next()
                return ask == 1 ? .sizes([:], pending: [path]) : .sizes([path: 9], pending: [])
            }
        }
        #expect(!model.hasAsked)
        await model.load()
        #expect(model.isLive)
        #expect(model.hasAsked)
        #expect(model.count == 3)
        #expect(model.extended == extended)
        #expect(model.total == 9)
    }

    /// Away with no answer, what was known stays, and Extended says it can't.
    @Test func keepsWhatItKnowsWithoutAnAnswer() async {
        let item = FileItem(
            path: FilePath("a.txt"), kind: .text, isDirectory: false, size: 5, created: nil,
            modified: nil, isReadOnly: false)
        let model = await model(item, reachable: false) { _ in throw FilesConnectionError.noAnswer }
        await model.load()
        #expect(model.hasAsked)
        #expect(!model.isLive)
        #expect(model.item == item)
        #expect(model.total == 5)
    }

    @Test func saysWhenAnItemIsMissing() async {
        let model = await model(folder(FilePath("gone"))) { _ in .missing }
        await model.load()
        #expect(model.isMissing)
    }
}
