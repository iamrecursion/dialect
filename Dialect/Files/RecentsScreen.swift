import SwiftUI

/// The files and sessions opened last, newest first, as many as Settings ›
/// History › Show Last says, under the pinned ones. A tap opens one; swiping
/// left hides it, and swiping right provides options to show it in its folder
/// or pin it.
struct RecentsScreen: View {
    @Environment(Navigation.self) private var navigation
    @AppStorage(FileSettings.showExtensionsKey) private var showExtensions =
        FileSettings.showExtensionsDefault
    @AppStorage(FileSettings.showHiddenKey) private var showHidden =
        FileSettings.showHiddenDefault
    @AppStorage(RecentsSettings.showLastKey) private var showLast =
        RecentsSettings.showLastDefault

    /// `nil` until the first read finishes.
    @State private var listing: Recents.Listing?

    /// The file open in a viewer.
    @State private var viewing: FilePath?
    @State private var failure: OperationFailure?

    var body: some View {
        List {
            if let listing {
                if listing.pinned.isEmpty && listing.recent.isEmpty {
                    Text("No Recent Items")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .listRowBackground(Color.clear)
                }
                if !listing.pinned.isEmpty {
                    Section("Pinned") {
                        rows(listing.pinned, pinned: true)
                    }
                }
                Section {
                    rows(listing.recent, pinned: false)
                } header: {
                    if !listing.pinned.isEmpty && !listing.recent.isEmpty {
                        Text("Recent")
                    }
                }
            }
        }
        .navigationTitle("Recents")
        // Reads again each time it's back on top, and when what it shows changes.
        .task(id: LoadKey(isOnTop: isOnTop, showHidden: showHidden, showLast: showLast)) {
            if isOnTop { await load() }
        }
        // What was opened has moved to the top.
        .fullScreenCover(item: $viewing, onDismiss: { Task { await load() } }) {
            FilePlaceholder(path: $0)
        }
        .operationFailureAlert($failure)
    }

    /// What reloading depends on.
    private struct LoadKey: Equatable {
        let isOnTop: Bool
        let showHidden: Bool
        let showLast: Int
    }

    private var isOnTop: Bool { navigation.path.last == .recents }

    private func rows(_ items: [FileItem], pinned: Bool) -> some View {
        return ForEach(items) { item in
            RecentRow(
                item: item, showExtensions: showExtensions, isPinned: pinned,
                open: { open(item) }, hide: { hide(item) }, show: { show(item) },
                pin: { pin(item, !pinned) })
        }
    }

    private func open(_ item: FileItem) {
        // A second tap arrives once what the first opened is on top.
        guard isOnTop, viewing == nil else { return }
        switch item.kind {
        // Only files and sessions are recorded, but something else may have put a folder at the
        // path since. It's shown in its folder, which keeps the path the folders, as Path needs.
        case .folder:
            navigation.show(item.path)
            return
        case .session: navigation.push(.session(item.path))
        default: viewing = item.path
        }
        FilesRoot.opened(item.path)
    }

    /// The row leaves at once, then Recents is read again, so a read begun
    /// before the write can't bring it back.
    private func hide(_ item: FileItem) {
        remove(item)
        Task {
            do {
                try await FilesRoot.operations.hideRecent(item.path)
            } catch {
                failure = OperationFailure("Couldn't Hide", error)
            }
            await load()
        }
    }

    /// Opens the item's folder in place of Recents, unless it's gone since
    /// Recents was read.
    private func show(_ item: FileItem) {
        guard isOnTop else { return }
        let root = FilesRoot.url
        Task {
            let exists = await Task.detached { Clipboard.exists(item.path, in: root) }.value
            guard isOnTop else { return }
            guard exists else {
                remove(item)
                failure = OperationFailure("Couldn't Show", FileOperationError.gone(item.name))
                return
            }
            navigation.show(item.path)
        }
    }

    /// Pins or unpins it, then reads again, as it moves between the sections.
    private func pin(_ item: FileItem, _ pinning: Bool) {
        Task {
            do {
                if pinning {
                    try await FilesRoot.operations.pin(item.path)
                } else {
                    try await FilesRoot.operations.unpin(item.path)
                }
            } catch {
                failure = OperationFailure(pinning ? "Couldn't Pin" : "Couldn't Unpin", error)
            }
            await load()
        }
    }

    private func remove(_ item: FileItem) {
        listing?.pinned.removeAll { $0.path == item.path }
        listing?.recent.removeAll { $0.path == item.path }
    }

    private func load() async {
        let recents = FilesRoot.operations.recents
        let root = FilesRoot.url
        let textExtensions = FileSettings.textExtensions()
        let (showHidden, showLast) = (self.showHidden, self.showLast)
        listing = await Task.detached(priority: .userInitiated) {
            recents.listing(
                root: root, textExtensions: textExtensions, showHidden: showHidden,
                limit: showLast)
        }.value
    }
}

/// An item in Recents: its icon, its name, and where it is.
private struct RecentRow: View {
    let item: FileItem
    let showExtensions: Bool
    let isPinned: Bool
    let open: () -> Void
    let hide: () -> Void
    let show: () -> Void
    let pin: () -> Void

    @Environment(\.dialectAccent) private var accent

    /// As `FileRow`'s, so Recents lines up with folders.
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 30

    private var name: String { item.displayName(showExtensions: showExtensions) }

    private var place: String { ClipboardScreen.heading(for: item.path.parent ?? .root) }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                FileIcon(kind: item.kind)
                    .font(.title3)
                    .frame(width: iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(verbatim: place)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: hide) {
                Label("Hide", systemImage: RecentsSymbol.hide)
            }
            .tint(.gray)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: show) {
                Label("Show in Files", systemImage: RecentsSymbol.showInFiles)
            }
            .tint(accent)
            Button(action: pin) {
                Label(
                    isPinned ? "Unpin" : "Pin",
                    systemImage: isPinned ? RecentsSymbol.unpin : RecentsSymbol.pin)
            }
            .tint(.gray)
        }
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: "\(String(localized: item.kind.typeName)), \(place)"))
        .accessibilityAction(named: Text("Hide"), hide)
        .accessibilityAction(named: Text("Show in Files"), show)
        .accessibilityAction(named: Text(isPinned ? "Unpin" : "Pin"), pin)
    }
}

/// Recents' icons.
enum RecentsSymbol {
    static let recents = "clock.arrow.trianglehead.counterclockwise.rotate.90"
    static let showInFiles = "folder"
    static let hide = "eye.slash"
    static let pin = "pin"
    static let unpin = "pin.slash"
}
