import SwiftUI
import WatchKit

/// What a folder held when it was last read.
enum FolderContents: Sendable {
    /// The items (files and folders) in the queried folder.
    case items([FileItem], FolderViewSettings)

    /// The folder isn't there any more, such as when something else deleted it
    /// while it was on the navigation path.
    case missing

    /// It's there but couldn't be read.
    case failed(String)
}

/// Reading a folder for its screen. Synchronous, so the screen calls it off the
/// main actor.
enum FolderLoader {
    static func load(
        _ folder: FilePath, root: URL, showHidden: Bool, textExtensions: Set<String>
    ) -> FolderContents {
        let url = folder.url(in: root)
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(
                atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return .missing }
        do {
            let items = try FileListing.items(
                in: folder, root: root, showHidden: showHidden, textExtensions: textExtensions,
                checking: .shared)
            return .items(items, FolderViewSettings.read(at: url))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// A folder: Add, Clipboard and More, then its items, sorted and grouped as its
/// view settings say. It's read again each time it's back on top, so changes
/// made elsewhere show.
///
/// In select mode the buttons are Done, Copy and More, and a tap on a row
/// toggles it.
struct FolderScreen: View {
    let path: FilePath

    /// Clipboard fills, with a count, while the clipboard holds items. In
    /// select mode, Copy is grayed out with nothing selected.
    static func buttons(
        for path: FilePath, clipboardCount: Int, selecting: Bool = false, selectedCount: Int = 0
    ) -> [MenuItem] {
        let here = Route.folderRoute(for: path)
        let more = MenuItem(title: "More", systemImage: "ellipsis.circle", route: .folderMore(path))
        if selecting {
            return [
                MenuItem(title: "Done", systemImage: SelectSymbol.done, route: here, action: .done),
                MenuItem(
                    title: "Copy", systemImage: ClipboardSymbol.copy, route: here,
                    isDisabled: selectedCount == 0, action: .copy),
                more,
            ]
        }
        let holding = clipboardCount > 0
        return [
            MenuItem(title: "Add", systemImage: "plus.capsule", route: .add(path)),
            // The clip sticks up above the board, which then sits low beside the other icons.
            MenuItem(
                title: "Clipboard",
                systemImage: holding ? "list.clipboard.fill" : "list.clipboard",
                route: .clipboard(path), opticalOffset: -1.5,
                count: holding ? clipboardCount : nil),
            more,
        ]
    }

    @Environment(Navigation.self) private var navigation
    @Environment(FileSelection.self) private var selection
    @Environment(\.dialectAccent) private var accent

    @AppStorage(FileSettings.showExtensionsKey) private var showExtensions =
        FileSettings.showExtensionsDefault
    @AppStorage(FileSettings.showDetailsKey) private var showDetails =
        FileSettings.showDetailsDefault
    @AppStorage(FileSettings.relativeModifiedKey) private var relativeModified =
        FileSettings.relativeModifiedDefault
    @AppStorage(FileSettings.foldersFirstKey) private var foldersFirst =
        FileSettings.foldersFirstDefault
    @AppStorage(FileSettings.showHiddenKey) private var showHidden =
        FileSettings.showHiddenDefault
    @AppStorage(FileSettings.dateStyleKey) private var dateStyle = FileSettings.dateStyleDefault
    @AppStorage(FileSettings.use24HourKey) private var use24Hour = FileSettings.use24HourDefault

    /// `nil` until the first read finishes.
    @State private var contents: FolderContents?

    /// Folders' and sessions' totals, filled in as they're worked out.
    @State private var sizes: [FilePath: Int64] = [:]

    /// The file open in a viewer.
    @State private var viewing: FilePath?

    /// Items being deleted: their rows leave at once, before the bin has them,
    /// and stay gone through the re-reads in between.
    @State private var deleting: Set<FilePath> = []
    @State private var failure: OperationFailure?

    /// Counts reads begun, so one that finishes after a newer has begun is
    /// dropped: a delete's re-read may overtake another's.
    @State private var reads = 0

    /// How many items the clipboard holds that are still there.
    @State private var clipboardCount = 0

    /// The longest title `TitleFitter` found to fit.
    @State private var fittingTitle: String?

    /// The item Show in Files brought into view, and how lit its highlight is.
    @State private var highlighted: FilePath?
    @State private var highlight = 0.0

    var body: some View {
        ScrollViewReader { proxy in
            screen
                .task(id: highlighted) {
                    if let highlighted { await reveal(highlighted, with: proxy) }
                }
                .onChange(of: navigation.revealing, initial: true) { startReveal() }
        }
    }

    private var screen: some View {
        ActionList(
            actions: Self.buttons(
                for: path, clipboardCount: clipboardCount, selecting: isSelecting,
                selectedCount: selection.items.count),
            perform: perform
        ) {
            rows
        }
        .navigationTitle(title)
        .background {
            TitleFitter(titles: Self.titles(for: path, showExtensions: showExtensions)) {
                fittingTitle = $0
            }
        }
        .onChange(of: isSelecting) { _, selecting in
            if selecting { listForSelection() }
        }
        // Delete Selected, handed back from More.
        .onChange(of: selection.deletion?.screen, initial: true) {
            if let paths = selection.takeDeletion(on: route) { delete(paths) }
        }
        // Re-reads whenever the folder comes back to the top of the path, and when Show Hidden
        // changes. `.task` alone doesn't rerun when a screen pushed over it is popped (watchOS 27).
        .task(id: LoadKey(showHidden: listsHidden, isOnTop: isOnTop)) {
            if isOnTop { await load() }
        }
        .fullScreenCover(item: $viewing) { FilePlaceholder(path: $0) }
        .operationFailureAlert($failure)
    }

    /// What reloading depends on.
    private struct LoadKey: Equatable {
        let showHidden: Bool
        let isOnTop: Bool
    }

    private var route: Route { Route.folderRoute(for: path) }

    /// Whether this folder is the top screen.
    private var isOnTop: Bool {
        return navigation.path.last == route
    }

    private var isSelecting: Bool { selection.isSelecting(on: route) }

    /// Show Hidden, or Show in Files having brought a hidden item into view
    /// here.
    private var listsHidden: Bool { showHidden || navigation.showsHidden(in: path) }

    /// The longest of `titles` that fits; "2 Selected" in select mode. A plain
    /// string, as a title view vanishes when screens under the folder are
    /// dropped (watchOS 27).
    private var title: String {
        if isSelecting { return FileSelection.title(selected: selection.items.count) }
        let titles = Self.titles(for: path, showExtensions: showExtensions)
        return fittingTitle.flatMap { titles.contains($0) ? $0 : nil } ?? titles[titles.count - 1]
    }

    /// The titles to try, longest first: the whole path, then with the folders
    /// nearest the root dropped for "…", down to the folder alone. "Files" at
    /// the root.
    nonisolated static func titles(for path: FilePath, showExtensions: Bool) -> [String] {
        let names = path.components.map { displayName(of: $0, showExtensions: showExtensions) }
        guard !names.isEmpty else { return [String(localized: "Files")] }
        return ["/" + names.joined(separator: "/")]
            + names.indices.dropFirst().map { "…/" + names[$0...].joined(separator: "/") }
    }

    /// The highlighted row's platter, while lit. The accent is a fixed color,
    /// so default environment values resolve it.
    private var highlightColor: Color? {
        guard highlight > 0 else { return nil }
        return Color(
            RowHighlight.color(accent: accent.resolve(in: EnvironmentValues()), amount: highlight))
    }

    /// A folder's or entered session's name, as rows show it.
    nonisolated static func displayName(of name: String, showExtensions: Bool) -> String {
        let kind = FileKind.classify(name: name, isDirectory: true, textExtensions: [])
        return kind == .session && !showExtensions ? FileItem.splitName(name).base : name
    }

    @ViewBuilder private var rows: some View {
        switch contents {
        case nil:
            EmptyView()
        case .missing:
            message("This folder no longer exists")
        case .failed(let reason):
            message("This folder couldn't be read: \(reason)")
        case .items(let items, _) where items.allSatisfy({ deleting.contains($0.path) }):
            message("No Items")
        case .items(let items, let settings):
            let style = rowStyle
            ForEach(
                FolderArrangement.sections(
                    items.filter { !deleting.contains($0.path) }, settings: settings,
                    foldersFirst: foldersFirst, now: style.now, sizes: sizes)
            ) { section in
                Section {
                    ForEach(section.items) { item in
                        FileRow(
                            item: item, size: item.isDirectory ? sizes[item.path] : item.size,
                            style: style,
                            isSelected: isSelecting ? selection.items.contains(item.path) : nil,
                            highlight: highlighted == item.path ? highlightColor : nil,
                            open: { open(item) }, more: { navigation.push(.itemMore(item.path)) },
                            delete: { delete([item.path]) }, copy: { copy(item) },
                            select: { selection.begin(on: route, with: item.path) })
                    }
                } header: {
                    if let group = section.group {
                        Text(group.title)
                    }
                }
            }
        }
    }

    private var rowStyle: FileRowStyle {
        return FileRowStyle(
            showExtensions: showExtensions, showDetails: showDetails,
            relativeModified: relativeModified, dateStyle: dateStyle, use24Hour: use24Hour,
            now: Date())
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        return Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .listRowBackground(Color.clear)
    }

    private func perform(_ button: MenuItem) {
        switch button.action {
        case .done: selection.end()
        case .copy: copySelected()
        case .select, nil: navigation.push(button.route)
        }
    }

    private func open(_ item: FileItem) {
        // The tap ending a long press arrives once More is on top; it isn't an open.
        guard isOnTop else { return }
        if isSelecting {
            selection.toggle(item.path)
            return
        }
        switch item.kind {
        case .folder: navigation.push(.folder(item.path))
        case .session:
            navigation.push(.session(item.path))
            FilesRoot.opened(item.path)
        default:
            viewing = item.path
            FilesRoot.opened(item.path)
        }
    }

    /// Deleting never asks. A failure brings the rows back with that read.
    private func delete(_ paths: [FilePath]) {
        guard !paths.isEmpty else { return }
        deleting.formUnion(paths)
        Task {
            do {
                _ = try await FilesRoot.operations.delete(paths)
            } catch {
                failure = OperationFailure("Couldn't Delete", error)
            }
            await load()
            deleting.subtract(paths)
        }
    }

    /// Puts the selection on the clipboard and leaves select mode.
    private func copySelected() {
        let paths = selection.selected
        guard !paths.isEmpty else { return }
        selection.end()
        Task {
            do {
                try await FileOperations.copyWithTap(paths)
            } catch {
                failure = OperationFailure("Couldn't Copy", error)
            }
            await load()
        }
    }

    /// Tells the selection what the folder lists, so items that have gone leave
    /// it, all of them when the folder is gone or can't be read.
    private func listForSelection() {
        guard isSelecting, let contents else { return }
        guard case .items(let items, _) = contents else {
            selection.list([])
            return
        }
        selection.list(items.map(\.path).filter { !deleting.contains($0) })
    }

    /// Puts the item on the clipboard, then reads the folder again for the
    /// Clipboard button's count.
    private func copy(_ item: FileItem) {
        Task {
            do {
                try await FileOperations.copyWithTap([item.path])
            } catch {
                failure = OperationFailure("Couldn't Copy", error)
            }
            await load()
        }
    }

    /// Brings Show in Files' item into view once the folder's read. An item the
    /// folder doesn't list isn't highlighted.
    private func startReveal() {
        guard isOnTop, highlighted == nil, case .items(let items, _) = contents,
            let item = navigation.reveal(in: path)
        else { return }
        if items.contains(where: { $0.path == item }) {
            highlighted = item
        } else {
            navigation.endReveal()
        }
    }

    /// Checks the files a few at a time, handing their kinds over as they're
    /// found. `false` once a newer read has begun.
    private func checkKinds(_ unchecked: [FileItem], root: URL, read: Int) async -> Bool {
        var start = unchecked.startIndex
        while start < unchecked.endIndex {
            let batch = Array(unchecked[start..<min(start + 16, unchecked.endIndex)])
            start += batch.count
            let kinds = await Task.detached(priority: .userInitiated) {
                batch.map { ($0.path, FileKinds.shared.check($0, root: root)) }
            }.value
            guard !Task.isCancelled, read == reads,
                case .items(let items, let settings) = contents
            else { return false }
            let found = Dictionary(uniqueKeysWithValues: kinds)
            contents = .items(items.map { found[$0.path].map($0.checked(as:)) ?? $0 }, settings)
        }
        return true
    }

    /// Scrolls the item into the middle, lights it, then fades it out. A screen
    /// gone part way leaves the reveal for the one rebuilt in its place.
    private func reveal(_ item: FilePath, with proxy: ScrollViewProxy) async {
        defer {
            highlighted = nil
            highlight = 0
        }
        // Once the list has laid out its rows.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        withAnimation { proxy.scrollTo(item, anchor: .center) }
        highlight = 1
        try? await Task.sleep(for: .milliseconds(1300))
        for step in stride(from: 0.9, to: 0, by: -0.1) {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(50))
            highlight = step
        }
        navigation.endReveal()
    }

    /// Reads the folder off the main actor, then checks the files it couldn't
    /// tell the kind of and works out the sizes of the folders and sessions in
    /// it, which fill in as they arrive.
    private func load() async {
        reads += 1
        let read = reads
        let root = FilesRoot.url
        let (path, showHidden) = (self.path, listsHidden)
        let textExtensions = FileSettings.textExtensions()
        let clipboard = FilesRoot.operations.clipboard
        let (loaded, held) = await Task.detached(priority: .userInitiated) {
            (
                FolderLoader.load(
                    path, root: root, showHidden: showHidden, textExtensions: textExtensions),
                clipboard.existing(root: root).count
            )
        }.value

        // A newer read has started, such as for Show Hidden or a delete: this one is out of date.
        guard !Task.isCancelled, read == reads else { return }
        contents = loaded
        clipboardCount = held
        listForSelection()
        startReveal()
        guard case .items(let items, _) = loaded else { return }
        guard await checkKinds(items.filter(\.needsCheck), root: root, read: read) else { return }

        // Handed over in batches, as each change re-sorts the folder.
        var arrived: [FilePath: Int64] = [:]
        var lastHandedOver = ContinuousClock.now
        for item in items where item.isDirectory {
            guard
                let size = await FolderSizes.shared.size(
                    of: item.path.url(in: root), modified: item.modified)
            else { return }
            guard read == reads else { return }
            arrived[item.path] = size
            if ContinuousClock.now - lastHandedOver > .milliseconds(300) {
                sizes.merge(arrived) { $1 }
                arrived = [:]
                lastHandedOver = .now
            }
        }
        sizes.merge(arrived) { $1 }
    }
}

/// Finds the longest of a folder's titles that fits the navigation bar, which
/// stops growing at accessibility3, as watchOS scrolls a title too long to fit.
struct TitleFitter: View {
    let titles: [String]
    let fit: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(titles, id: \.self) { title in
                Text(verbatim: title)
                    .font(.body.weight(.medium))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .lineLimit(1)
                    .onAppear { fit(title) }
            }
        }
        .frame(width: Self.width(screen: WKInterfaceDevice.current().screenBounds.width))
        .hidden()
    }

    nonisolated static func width(screen: CGFloat) -> CGFloat {
        return 0.5 * screen + 29.5
    }
}
