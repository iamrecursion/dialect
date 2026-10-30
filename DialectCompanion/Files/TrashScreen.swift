import Observation
import SwiftUI

/// What's in the watch's bin, newest first, each with when it was deleted and
/// how long it has left.
struct TrashScreen: View {
    @Environment(WatchFiles.self) private var files

    @State private var model: BinModel

    init(model: BinModel) {
        _model = State(initialValue: model)
    }

    private var display: FilesDisplay { files.link.display }

    var body: some View {
        List {
            if shownItems.isEmpty, model.state == .loading {
                LoadingRows(showsDetails: true)
            }
            ForEach(shownItems) { item in
                ListRowLabel(lines: lines(for: item)) {
                    FileListIcon(kind: item.kind)
                } title: {
                    Text(verbatim: name(of: item))
                }
            }
        }
        .overlay {
            if shownItems.isEmpty, let message {
                ContentUnavailableView {
                    Text(message)
                }
            }
        }
        .navigationTitle("Trash")
        .lastSeenSubtitle(model.state, of: .trash)
        .browsing(model, files: files)
    }

    private var shownItems: [ListedBinItem] {
        return model.state == .unavailable ? [] : model.items
    }

    private func name(of item: ListedBinItem) -> String {
        return display.showExtensions || item.kind == .folder
            ? item.name : FileItem.splitName(item.name).base
    }

    private func lines(for item: ListedBinItem) -> [String] {
        return BinExpiry.detail(
            deleted: item.deleted, now: Date(), relative: display.relativeModified,
            style: display.dateStyle, use24Hour: display.use24Hour,
            emptyAfter: display.emptyTrashAfter)
    }

    private var message: LocalizedStringResource? {
        switch model.state {
        case .loading: return nil
        case .live, .cached: return "The Trash is empty"
        case .neverSeen: return "Open Dialect on your watch to see the Trash."
        case .missing, .unavailable: return FilesUnavailable.text
        case .failed(let reason): return "The Trash couldn't be read: \(reason)"
        }
    }
}

/// The watch's Trash on the phone.
@MainActor @Observable
final class BinModel: BrowsingModel {
    private(set) var items: [ListedBinItem] = []
    var status = BrowsingStatus()

    @ObservationIgnored var reads = 0
    @ObservationIgnored private let files: WatchFiles
    @ObservationIgnored private var token: String?

    init(files: WatchFiles) {
        self.files = files
    }

    func refresh() async {
        reads += 1
        let read = reads
        await files.cacheSettled()
        if token == nil, let cached = await files.cache.bin(), read == reads {
            items = cached.items
            token = cached.token
            status.showCache(seen: cached.seen)
        }
        guard read == reads, canAsk(files) else { return }
        let epoch = files.link.epoch
        let hadRows = token != nil
        let result: WatchFiles.ListingRead<ListedBinItem> = await files.readListing(
            token: token, body: { .bin(offset: $0, token: $1) },
            page: { reply in
                guard case .bin(let page) = reply else { return nil }
                return .init(items: page.items, token: page.token, total: page.total)
            },
            isCurrent: { [weak self] in self?.reads == read },
            partial: { [weak self] collected, _ in
                if !hadRows { self?.items = collected }
            })
        switch result {
        case .abandoned:
            return
        case .unchanged:
            status.heard()
        case .read(let listed, let token, _):
            items = listed
            self.token = token
            status.heard()
        case .noAnswer:
            if !hadRows { items = [] }
            status.noAnswer()
            return
        case .failed(let reason):
            if !hadRows { items = [] }
            status.failed(reason)
            return
        case .missing, .otherFormat:
            status.set(.unavailable)
            return
        }
        guard let token, let seen = status.seen else { return }
        await files.cache.store(CachedBin(items: items, token: token, seen: seen), epoch: epoch)
    }

    func reset() {
        items = []
        token = nil
        status.reset()
    }
}
