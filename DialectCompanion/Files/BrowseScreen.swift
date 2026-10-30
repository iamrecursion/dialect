import Observation
import SwiftUI

/// Where Files opens: the watch's Recents, then Files and the Trash.
struct BrowseScreen: View {
    @Environment(WatchFiles.self) private var files
    @Environment(FilesNavigation.self) private var navigation
    @Environment(PhoneLink.self) private var link

    @State private var model: RecentsModel
    @State private var opened: FileItem?
    @State private var info: FileItem?

    init(model: RecentsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            if model.state == .unavailable {
                Section {
                    FilesUnavailable()
                }
            } else {
                if !model.pinned.isEmpty {
                    Section("Pinned") { rows(model.pinned) }
                }
                if !model.recent.isEmpty {
                    Section("Recent") { rows(model.recent) }
                }
                Section("Locations") {
                    NavigationLink(value: FilesDestination.folder(.root)) {
                        ListRowLabel(lines: [link.watchName]) {
                            FileListIcon(kind: .folder)
                        } title: {
                            Text("Files")
                        }
                    }
                    NavigationLink(value: FilesDestination.trash) {
                        ListRowLabel {
                            Image(systemName: "trash")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        } title: {
                            Text("Trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Browse")
        .lastSeenSubtitle(model.state, of: .recents)
        .sheet(item: $opened) { ItemInfoSheet(item: $0, files: files, note: "No viewer yet") }
        .sheet(item: $info) { ItemInfoSheet(item: $0, files: files) }
        .browsing(model, files: files)
    }

    private func rows(_ items: [FileItem]) -> some View {
        ForEach(items) { item in
            Button {
                open(item)
            } label: {
                FileListRow(
                    item: item, detail: Self.location(of: item),
                    showExtensions: files.link.display.showExtensions)
            }
            .contextMenu {
                Button("Show in Files", systemImage: RecentsSymbol.showInFiles) {
                    navigation.show(item.path.parent ?? .root)
                }
                Button("Get Info", systemImage: "info.circle") { info = item }
            }
        }
    }

    /// Opening from Recents records nothing: the history is the watch's.
    private func open(_ item: FileItem) {
        switch item.kind {
        case .folder: navigation.show(item.path)
        case .session: navigation.path.append(.session(item.path))
        default: opened = item
        }
    }

    /// The line beneath a recent item's name.
    static func location(of item: FileItem) -> String {
        guard let parent = item.path.parent, parent != .root else {
            return String(localized: "In Files")
        }
        return String(localized: "In \(parent.display)")
    }
}

/// Why there's nothing to show, which the Watch tab explains.
struct FilesUnavailable: View {
    static let text: LocalizedStringResource =
        "Your watch's files aren't available. The Watch tab says why."

    var body: some View {
        Text(Self.text)
            .foregroundStyle(.secondary)
    }
}

/// The watch's Recents on the phone.
@MainActor @Observable
final class RecentsModel: BrowsingModel {
    private(set) var pinned: [FileItem] = []
    private(set) var recent: [FileItem] = []
    var status = BrowsingStatus()

    @ObservationIgnored var reads = 0
    @ObservationIgnored private let files: WatchFiles

    init(files: WatchFiles) {
        self.files = files
    }

    func refresh() async {
        reads += 1
        let read = reads
        await files.cacheSettled()
        if status.seen == nil, let cached = await files.cache.recents(), read == reads {
            pinned = cached.pinned
            recent = cached.recent
            status.showCache(seen: cached.seen)
        }
        guard read == reads, canAsk(files) else { return }
        let epoch = files.link.epoch
        let asked = await files.ask(.recents)
        guard read == reads else { return }
        switch asked {
        case .noAnswer:
            status.noAnswer()
        case .failed(let reason):
            status.failed(reason)
        case .reply(.recents(let pinned, let recent)):
            self.pinned = pinned
            self.recent = recent
            let now = Date()
            status.heard(at: now)
            let cached = CachedRecents(pinned: pinned, recent: recent, seen: now)
            await files.cache.store(cached, epoch: epoch)
        case .reply(.otherFormat):
            status.set(.unavailable)
        case .reply(.failed(let reason)):
            status.failed(reason)
        case .reply:
            status.failed(WatchFiles.unexpectedAnswer)
        }
    }

    func reset() {
        pinned = []
        recent = []
        status.reset()
    }
}
