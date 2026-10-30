import Observation
import SwiftUI

/// An item's Info on the phone: what's known at once, then the watch's data.
@MainActor @Observable
final class ItemInfoModel {
    let path: FilePath
    private(set) var item: FileItem
    private(set) var total: Int64?
    private(set) var count: Int?
    private(set) var extended: ExtendedInfo?
    private(set) var isMissing = false

    /// The watch has answered.
    private(set) var isLive = false

    /// The watch has been asked, and has answered or won't.
    private(set) var hasAsked = false

    @ObservationIgnored private let files: WatchFiles

    init(item: FileItem, files: WatchFiles) {
        path = item.path
        self.item = item
        total = item.size
        self.files = files
    }

    /// Asks the watch, then asks again for a total still being worked out while
    /// connected.
    func load() async {
        defer { hasAsked = true }
        guard files.canAsk,
            let reply = try? await files.connection.send(FilesRequest(body: .info(path)))
        else { return }
        switch reply {
        case .info(let info):
            item = info.item
            total = info.total
            count = info.count
            extended = info.extended
            isLive = true
        case .missing:
            isMissing = true
            return
        default:
            return
        }
        guard item.isDirectory else { return }
        while total == nil {
            guard
                let reply = try? await files.connection.send(FilesRequest(body: .sizes([path]))),
                case .sizes(let known, let pending) = reply
            else { return }
            total = known[path]
            guard total == nil, !pending.isEmpty, files.isConnected, !Task.isCancelled else {
                return
            }
            try? await Task.sleep(for: files.pendingRetry)
        }
    }
}

/// Info's rows: the header, the watch's fields and Extended.
struct ItemInfoRows: View {
    let model: ItemInfoModel
    var note: LocalizedStringResource?

    @Environment(WatchFiles.self) private var files

    private var display: FilesDisplay { files.link.display }

    var body: some View {
        if model.isMissing {
            Text("This item is no longer there.")
                .foregroundStyle(.secondary)
        } else {
            let item = model.item
            Section {
                VStack(spacing: 4) {
                    FileListIcon(kind: item.kind)
                        .font(.largeTitle)
                    Text(verbatim: name(of: item))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(verbatim: FileInfo.summary(for: item, size: model.total))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.clear)
            }
            Section {
                let fields = FileInfo.cardFields(
                    FileInfo.fields(
                        for: item, size: model.total, itemCount: model.count, date: display.date))
                ForEach(fields) { field in
                    LabeledContent {
                        Text(verbatim: field.value)
                    } label: {
                        Text(field.label.title)
                    }
                }
            }
            extendedSection
        }
    }

    private func name(of item: FileItem) -> String {
        if item.path == .root { return String(localized: "Files") }
        return item.displayName(showExtensions: display.showExtensions)
    }

    @ViewBuilder private var extendedSection: some View {
        if let extended = model.extended {
            Section("Permissions") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: extended.permissions)
                        .font(.body.monospaced())
                    ForEach(extended.access, id: \.self) { line in
                        Text(verbatim: line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                LabeledContent {
                    Text(verbatim: extended.owner)
                } label: {
                    Text("Owner")
                }
                LabeledContent {
                    Text(verbatim: extended.group)
                } label: {
                    Text("Group")
                }
            }
            Section("Extended Attributes") {
                if extended.attributes.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                }
                ForEach(extended.attributes, id: \.name) { attribute in
                    LabeledContent {
                        Text(
                            verbatim: ByteCountFormatter.string(
                                fromByteCount: Int64(attribute.size), countStyle: .file))
                    } label: {
                        Text(verbatim: attribute.name)
                    }
                }
            }
        } else if model.hasAsked, !model.isLive {
            Section("Extended") {
                Text("Your watch needs to be connected to show this.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Info as a sheet: Folder Info, or with a `note`, what opening a file shows
/// until it has a viewer.
struct ItemInfoSheet: View {
    var note: LocalizedStringResource?

    @State private var model: ItemInfoModel
    @Environment(\.dismiss) private var dismiss

    init(item: FileItem, files: WatchFiles, note: LocalizedStringResource? = nil) {
        self.note = note
        _model = State(initialValue: ItemInfoModel(item: item, files: files))
    }

    var body: some View {
        NavigationStack {
            List {
                ItemInfoRows(model: model, note: note)
            }
            .navigationTitle(note == nil ? Text("Info") : Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await model.load() }
    }
}
