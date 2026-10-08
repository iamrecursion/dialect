import SwiftUI

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
                in: folder, root: root, showHidden: showHidden, textExtensions: textExtensions)
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

    var body: some View {
        ActionList(
            actions: Self.buttons(
                for: path, clipboardCount: clipboardCount, selecting: isSelecting,
                selectedCount: selection.items.count),
            perform: perform
        ) {
            rows
        }
        .navigationTitle(title)
        .onChange(of: isSelecting) { _, selecting in
            if selecting { listForSelection() }
        }
        // Delete Selected, handed back from More.
        .onChange(of: selection.deletion?.screen, initial: true) {
            if let paths = selection.takeDeletion(on: route) { delete(paths) }
        }
        // Re-reads whenever the folder comes back to the top of the path, and when Show Hidden
        // changes. `.task` alone doesn't rerun when a screen pushed over it is popped (watchOS 27).
        .task(id: LoadKey(showHidden: showHidden, isOnTop: isOnTop)) {
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

    private var title: Text {
        if isSelecting {
            return Text(verbatim: FileSelection.title(selected: selection.items.count))
        }
        guard let name = path.name else { return Text("Files") }
        return Text(verbatim: FolderScreen.displayName(of: name, showExtensions: showExtensions))
    }

    /// A folder's or entered session's name, as rows show it.
    static func displayName(of name: String, showExtensions: Bool) -> String {
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
        case .session: navigation.push(.session(item.path))
        default: viewing = item.path
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

    /// Reads the folder off the main actor, then works out the sizes of the
    /// folders and sessions in it, which fill in as they arrive.
    private func load() async {
        reads += 1
        let read = reads
        let root = FilesRoot.url
        let (path, showHidden) = (self.path, self.showHidden)
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
        guard case .items(let items, _) = loaded else { return }

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
