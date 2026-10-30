import SwiftUI

/// A folder on the watch: its items, sorted and grouped like the watch's, under
/// its name and whose title menu lists the path.
struct FolderListScreen: View {
    @Environment(WatchFiles.self) private var files
    @Environment(FilesNavigation.self) private var navigation

    @State private var model: FolderModel
    @State private var opened: FileItem?
    @State private var info: FileItem?
    @State private var showsFolderInfo = false

    init(model: FolderModel) {
        _model = State(initialValue: model)
    }

    private var display: FilesDisplay { files.link.display }

    var body: some View {
        let sections = model.sections(now: Date())
        List {
            if sections.isEmpty, model.state == .loading {
                LoadingRows(showsDetails: display.showDetails)
            }
            ForEach(sections) { section in
                if let group = section.group {
                    Section {
                        rows(section.items)
                    } header: {
                        Text(group.title)
                    }
                } else {
                    rows(section.items)
                }
            }
        }
        .overlay {
            if sections.isEmpty, let message {
                ContentUnavailableView {
                    Text(message)
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .lastSeenSubtitle(model.state, of: .folder)
        .toolbarTitleMenu {
            // The path above this folder, nearest first, like the Files app's, then Browse.
            ForEach(Array(model.path.ancestors.reversed()), id: \.self) { folder in
                Button(folderName(folder), systemImage: "folder") {
                    navigation.show(folder)
                }
            }
            Button("Browse", systemImage: "list.bullet.below.rectangle") {
                navigation.path = []
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Folder Info", systemImage: "info.circle") {
                        showsFolderInfo = true
                    }
                }
            }
        }
        .sheet(item: $opened) { ItemInfoSheet(item: $0, files: files, note: "No viewer yet") }
        .sheet(item: $info) { ItemInfoSheet(item: $0, files: files) }
        .sheet(isPresented: $showsFolderInfo) {
            ItemInfoSheet(item: folderItem, files: files)
        }
        .browsing(model, files: files)
        // Details turned on, here or on the watch, needs totals.
        .onChange(of: display.showDetails) { _, showing in
            if showing { Task { await files.refresh(model) } }
        }
    }

    private var title: String { folderName(model.path) }

    private func folderName(_ folder: FilePath) -> String {
        guard let name = folder.name else { return String(localized: "Files") }
        return FileItem.displayName(of: name, showExtensions: display.showExtensions)
    }

    /// What its path says of this folder, as the watch may not answer.
    private var folderItem: FileItem {
        let kind = FileKind.classify(
            name: model.path.name ?? "", isDirectory: true, textExtensions: [])
        return FileItem(
            path: model.path, kind: kind ?? .folder, isDirectory: true, size: nil, created: nil,
            modified: nil, isReadOnly: false)
    }

    /// What the screen says with no rows to show.
    private var message: LocalizedStringResource? {
        switch model.state {
        case .loading: return nil
        case .live, .cached: return "No Items"
        case .neverSeen: return "Open Dialect on your watch to see this folder."
        case .missing: return "This folder no longer exists"
        case .failed(let reason): return "This folder couldn't be read: \(reason)"
        case .unavailable: return FilesUnavailable.text
        }
    }

    private func rows(_ items: [FileItem]) -> some View {
        ForEach(items) { item in
            row(item)
                .contextMenu {
                    Button("Get Info", systemImage: "info.circle") { info = item }
                }
        }
    }

    @ViewBuilder private func row(_ item: FileItem) -> some View {
        let label = FileListRow(
            item: item,
            detail: display.showDetails
                ? display.rowStyle(now: Date()).detail(
                    for: item, size: item.isDirectory ? model.sizes[item.path] : item.size)
                : nil,
            showExtensions: display.showExtensions)
        switch item.kind {
        case .folder:
            NavigationLink(value: FilesDestination.folder(item.path)) { label }
        case .session:
            // Opened like a file, so without a folder's chevron.
            Button {
                navigation.path.append(.session(item.path))
            } label: {
                label
            }
        default:
            Button {
                opened = item
            } label: {
                label
            }
        }
    }
}
