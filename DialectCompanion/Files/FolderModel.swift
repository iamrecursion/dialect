import Foundation
import Observation

/// One folder on the phone: its cached rows at once, then the watch's, page by
/// page with folders' total, as they arrive.
@MainActor @Observable
final class FolderModel: BrowsingModel {
    let path: FilePath

    private(set) var items: [FileItem] = []
    private(set) var settings = FolderViewSettings()
    private(set) var sizes: [FilePath: Int64] = [:]
    var status = BrowsingStatus()

    @ObservationIgnored var reads = 0
    @ObservationIgnored private let files: WatchFiles

    /// The listing the rows are from.
    @ObservationIgnored private var token: String?

    init(path: FilePath, files: WatchFiles) {
        self.path = path
        self.files = files
    }

    /// The rows to show: hidden items are always listed, and the phone filters
    /// them.
    func sections(now: Date) -> [FileSection] {
        guard state != .unavailable else { return [] }
        let display = files.link.display
        let shown = display.showHidden ? items : items.filter { !$0.isHidden }
        return FolderArrangement.sections(
            shown, settings: settings, foldersFirst: display.foldersFirst, now: now, sizes: sizes)
    }

    /// Totals are needed only where they show.
    private var wantsSizes: Bool {
        return files.link.display.showDetails || settings.sort == .size
    }

    /// Shows the cache, if it hasn't shown anything yet, then asks the watch.
    func refresh() async {
        reads += 1
        let read = reads
        await files.cacheSettled()
        await files.cache.keep(onScreen: [path])
        if token == nil, let cached = await files.cache.folder(path), read == reads {
            show(cached)
        }
        await files.cache.shown(path)
        guard read == reads, canAsk(files) else { return }

        let epoch = files.link.epoch
        let hadRows = token != nil
        let path = path
        let result: WatchFiles.ListingRead<ListedItem> = await files.readListing(
            token: token, body: { .list(path, offset: $0, token: $1) },
            page: { reply in
                guard case .listing(let page) = reply else { return nil }
                return .init(
                    items: page.items, token: page.token, total: page.total,
                    settings: page.settings)
            },
            isCurrent: { [weak self] in self?.reads == read },
            partial: { [weak self] collected, settings in
                // Rows already showing stay until the whole listing is in.
                guard !hadRows, let self else { return }
                self.items = collected.map { $0.item(in: path) }
                self.settings = settings ?? self.settings
            })

        switch result {
        case .abandoned:
            return
        case .unchanged:
            status.heard()
        case .read(let listed, let token, let settings):
            items = listed.map { $0.item(in: path) }
            self.settings = settings ?? self.settings
            self.token = token
            let present = Set(items.map(\.path))
            sizes = sizes.filter { present.contains($0.key) }
            status.heard()
        case .missing:
            clearRows()
            status.missing()
            await files.cache.remove(path)
            return
        case .noAnswer:
            // A part of a folder would read as all of it.
            if !hadRows { clearRows() }
            status.noAnswer()
            return
        case .failed(let reason):
            if !hadRows { clearRows() }
            status.failed(reason)
            return
        case .otherFormat:
            status.set(.unavailable)
            return
        }
        await store(epoch: epoch)
        guard status.state == .live else { return }
        await askForSizes(read: read, epoch: epoch)
    }

    func reset() {
        clearRows()
        status.reset()
    }

    private func clearRows() {
        items = []
        sizes = [:]
        settings = FolderViewSettings()
        token = nil
    }

    private func show(_ cached: CachedFolder) {
        items = cached.items.map { $0.item(in: path) }
        settings = cached.settings
        sizes = cached.sizes
        token = cached.token
        status.showCache(seen: cached.seen)
    }

    private func store(epoch: String?) async {
        guard let token, let seen = status.seen else { return }
        let cached = CachedFolder(
            items: items.map(ListedItem.init), settings: settings, token: token, sizes: sizes,
            seen: seen)
        await files.cache.store(cached, at: path, epoch: epoch)
    }

    /// Asks for the totals of the folders and sessions showing, and again for
    /// those still pending while connected.
    private func askForSizes(read: Int, epoch: String?) async {
        guard wantsSizes else { return }
        var wanted = items.filter(\.isDirectory).map(\.path)
        while !wanted.isEmpty {
            var pending: [FilePath] = []
            for batch in FilesPaging.batches(of: wanted) {
                guard
                    let reply = try? await files.connection.send(
                        FilesRequest(body: .sizes(batch))), read == reads,
                    case .sizes(let known, let waiting) = reply
                else { return }
                sizes.merge(known) { $1 }
                pending += waiting
            }
            await store(epoch: epoch)
            wanted = pending
            guard !wanted.isEmpty, files.isConnected else { return }
            try? await Task.sleep(for: files.pendingRetry)
            guard read == reads else { return }
        }
    }
}
