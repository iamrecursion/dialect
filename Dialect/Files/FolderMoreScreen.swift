import SwiftUI

/// A folder's More screen.
///
/// What opens a screen replaces More on the path, and what only acts pops it,
/// so More never stays in the history.
struct FolderMoreScreen: View {
    let path: FilePath

    enum Action: CaseIterable {
        case selectAll, deselectAll, share, deleteSelected
        case sort, group, showHidden, folderInfo, path, delete, trash, settings

        /// Show Hidden's title is for when hidden items are hidden; the screen
        /// shows Hide Hidden while they're shown.
        var title: LocalizedStringResource {
            switch self {
            case .selectAll: return "Select All"
            case .deselectAll: return "Deselect All"
            case .share: return "Share"
            case .deleteSelected: return "Delete Selected"
            case .sort: return "Sort"
            case .group: return "Group"
            case .showHidden: return "Show Hidden"
            case .folderInfo: return "Folder Info"
            case .path: return "Path"
            case .delete: return "Delete"
            case .trash: return "Trash"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .selectAll: return "checklist.checked"
            case .deselectAll: return "checklist.unchecked"
            case .share: return ShareSymbol.share
            case .deleteSelected: return "trash"
            case .sort: return "arrow.up.arrow.down"
            case .group: return "square.grid.3x1.below.line.grid.1x2"
            case .showHidden: return "eye"
            case .folderInfo: return "info.circle"
            case .path: return "list.bullet.indent"
            case .delete: return "trash"
            case .trash: return "trash.fill"
            case .settings: return "gear"
            }
        }
    }

    /// Select mode's section: Select All, or Deselect All once everything is
    /// selected, then Share and Delete Selected.
    static func selectActions(hasEverything: Bool) -> [Action] {
        return [hasEverything ? .deselectAll : .selectAll, .share, .deleteSelected]
    }

    /// The section with Delete, which the root doesn't have, and which select
    /// mode hides so it can't be mistaken for Delete Selected.
    static func deleteActions(isRoot: Bool, selecting: Bool) -> [Action] {
        return isRoot || selecting ? [.trash] : [.delete, .trash]
    }

    /// Whether More shares the folder itself, zipped. The root has no Share,
    /// and in select mode Share sends the selection instead.
    static func sharesFolder(isRoot: Bool, selecting: Bool) -> Bool {
        return !isRoot && !selecting
    }

    /// What acts on the selection is grayed out with nothing selected.
    static func isDisabled(_ action: Action, selectedCount: Int) -> Bool {
        return [.share, .deleteSelected].contains(action) && selectedCount == 0
    }

    @Environment(Navigation.self) private var navigation
    @Environment(FileSelection.self) private var selection
    @AppStorage(FileSettings.showHiddenKey) private var showHidden =
        FileSettings.showHiddenDefault

    @State private var binIsEmpty = true

    /// What Share sends, worked out as the screen appears in select mode.
    @State private var shared: Shared?

    /// Set once Share has sent the selection: select mode ends as More is left.
    @State private var sent = false
    @State private var failure: OperationFailure?
    @State private var deleting = false

    var body: some View {
        List {
            if isSelecting {
                Section {
                    ForEach(
                        Self.selectActions(hasEverything: selection.hasEverything), id: \.self
                    ) { action in
                        Group {
                            if action == .share {
                                shareRow
                            } else {
                                row(action)
                            }
                        }
                        .disabled(Self.isDisabled(action, selectedCount: selection.items.count))
                    }
                }
            }
            UndoRows(here: path)
                .disabled(deleting)
            Section {
                ForEach([Action.sort, .group, .showHidden, .folderInfo], id: \.self, content: row)
                if Self.sharesFolder(isRoot: path == .root, selecting: isSelecting) {
                    ShareRow(shared: .archive([path], name: Shared.archiveName(of: path)))
                }
                row(.path)
            }
            Section {
                if Self.deleteActions(isRoot: path == .root, selecting: isSelecting).contains(
                    .delete)
                {
                    row(.delete)
                        .disabled(deleting)
                }
                row(.trash)
                    .disabled(binIsEmpty)
            }
            // At the bottom, on its own.
            Section {
                row(.settings)
            }
        }
        .navigationTitle("More")
        .operationFailureAlert($failure)
        .onDisappear {
            if sent { selection.end() }
        }
        .task {
            let bin = FilesRoot.operations.bin
            let days = FileSettings.emptyTrashAfter()
            let (paths, root) = (isSelecting ? selection.selected : [], FilesRoot.url)
            async let empty = Task.detached {
                bin.items().allSatisfy { $0.isExpired(now: Date(), after: days) }
            }.value
            async let sending = Task.detached {
                Shared.of(paths) { path in
                    FileOperations.kind(at: path.url(in: root)).map { $0 != .file } ?? false
                }
            }.value
            shared = await sending
            binIsEmpty = await empty
        }
    }

    /// Grayed out until what it sends is worked out.
    @ViewBuilder private var shareRow: some View {
        if let shared {
            ShareRow(shared: shared) { sent = true }
        } else {
            Button {
            } label: {
                MenuRowLabel(title: "Share", systemImage: ShareSymbol.share)
            }
            .disabled(true)
        }
    }

    private var isSelecting: Bool {
        return selection.isSelecting(on: Route.folderRoute(for: path))
    }

    private func row(_ action: Action) -> some View {
        return Button {
            perform(action)
        } label: {
            if action == .showHidden && showHidden {
                MenuRowLabel(title: "Hide Hidden", systemImage: "eye.slash")
            } else {
                MenuRowLabel(title: action.title, systemImage: action.systemImage)
            }
        }
    }

    private func perform(_ action: Action) {
        switch action {
        case .selectAll:
            selection.selectAll()
            navigation.pop()
        case .deselectAll:
            selection.deselectAll()
            navigation.pop()
        case .share:
            // The row is a `ShareLink`, which acts by itself.
            break
        case .deleteSelected:
            // The folder deletes them, so their rows leave as More closes.
            selection.deleteSelected()
            navigation.pop()
        case .sort: navigation.replaceTop(with: .sort(path))
        case .group: navigation.replaceTop(with: .group(path))
        case .showHidden:
            showHidden.toggle()
            navigation.pop()
        case .folderInfo: navigation.replaceTop(with: .folderInfo(path))
        case .path: navigation.replaceTop(with: .path(path))
        case .delete: delete()
        case .trash: navigation.replaceTop(with: .bin)
        case .settings: navigation.replaceTop(with: .settings)
        }
    }

    /// Deletes this folder and leaves it, so the path ends on its parent.
    private func delete() {
        guard !deleting else { return }
        deleting = true
        Task {
            defer { deleting = false }
            do {
                _ = try await FilesRoot.operations.delete([path])
                navigation.leave(path)
            } catch {
                failure = OperationFailure("Couldn't Delete", error)
            }
        }
    }
}

/// A folder's sort settings: the key, then the direction. Choosing saves it and
/// goes back to the folder.
struct SortScreen: View {
    let path: FilePath

    var body: some View {
        ViewSettingsScreen(path: path, title: "Sort") { settings, choose in
            Section {
                ForEach(FolderViewSettings.SortKey.allCases, id: \.self) { key in
                    ChoiceRow(title: key.title, isChosen: settings.sort == key) {
                        choose { $0.sort = key }
                    }
                }
            }
            Section {
                ChoiceRow(title: "Ascending", isChosen: settings.ascending) {
                    choose { $0.ascending = true }
                }
                ChoiceRow(title: "Descending", isChosen: !settings.ascending) {
                    choose { $0.ascending = false }
                }
            }
        }
    }
}

/// A folder's grouping, kept on the folder.
struct GroupScreen: View {
    let path: FilePath

    var body: some View {
        ViewSettingsScreen(path: path, title: "Group") { settings, choose in
            ForEach(FolderViewSettings.Grouping.allCases, id: \.self) { grouping in
                ChoiceRow(title: grouping.title, isChosen: settings.grouping == grouping) {
                    choose { $0.grouping = grouping }
                }
            }
        }
    }
}

/// A row that's one of several choices.
private struct ChoiceRow: View {
    let title: LocalizedStringResource
    let isChosen: Bool
    let choose: () -> Void

    @Environment(\.dialectAccent) private var accent

    var body: some View {
        Button(action: choose) {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                if isChosen {
                    Image(systemName: "checkmark")
                        .foregroundStyle(accent)
                }
            }
        }
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

/// Sort's and Group's shared workings: reads the folder's view settings, and
/// saves a choice to the folder before going back to it.
private struct ViewSettingsScreen<Content: View>: View {
    typealias Choose = (_ change: (inout FolderViewSettings) -> Void) -> Void

    let path: FilePath
    let title: LocalizedStringResource
    let content: (FolderViewSettings, @escaping Choose) -> Content

    @Environment(Navigation.self) private var navigation
    @State private var settings: FolderViewSettings
    @State private var failure: String?

    init(
        path: FilePath, title: LocalizedStringResource,
        @ViewBuilder content: @escaping (FolderViewSettings, @escaping Choose) -> Content
    ) {
        self.path = path
        self.title = title
        self.content = content
        // Read at once, as it's one small attribute, so the screen's first frame has its rows.
        _settings = State(initialValue: FolderViewSettings.read(at: path.url(in: FilesRoot.url)))
    }

    var body: some View {
        List {
            content(settings, choose)
        }
        .navigationTitle(Text(title))
        .alert(
            "Couldn't Save",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
            actions: { Button("OK") {} },
            message: { Text(verbatim: failure ?? "") })
    }

    private func choose(_ change: (inout FolderViewSettings) -> Void) {
        var updated = settings
        change(&updated)
        do {
            try updated.write(to: path.url(in: FilesRoot.url))
            navigation.pop()
        } catch {
            failure = error.localizedDescription
        }
    }
}
