import SwiftUI

/// An item as Info shows it: the item, and the totals that take longer to work
/// out.
struct LoadedInfo: Sendable, Equatable {
    /// The item described.
    let item: FileItem

    /// A file's size, or a folder's or session's total once worked out.
    let size: Int64?

    /// Folder Info's count of entries.
    let itemCount: Int?

    /// Reads an item for Info off the main actor; `nil` when it's gone. A
    /// folder's total is left for `withTotal(root:)`, so Info can show first.
    static func load(_ path: FilePath, root: URL, countsItems: Bool) async -> LoadedInfo? {
        let textExtensions = FileSettings.textExtensions()
        return await Task.detached {
            guard
                let item = try? FileListing.item(
                    at: path, root: root, textExtensions: textExtensions)
            else { return nil }
            let itemCount = countsItems ? FileInfo.itemCount(at: path.url(in: root)) : nil
            return LoadedInfo(item: item, size: item.size, itemCount: itemCount)
        }.value
    }

    /// With a folder's or session's total worked out, from the cache when it
    /// can be.
    func withTotal(root: URL) async -> LoadedInfo {
        guard item.isDirectory else { return self }
        let total = await FolderSizes.shared.size(
            of: item.path.url(in: root), modified: item.modified)
        return LoadedInfo(item: item, size: total ?? size, itemCount: itemCount)
    }

    /// Reads an item, hands it over, then hands it over again with its total.
    @MainActor
    static func load(
        _ path: FilePath, countsItems: Bool, into deliver: (LoadedInfo?) -> Void
    ) async {
        let root = FilesRoot.url
        let info = await load(path, root: root, countsItems: countsItems)
        deliver(info)
        guard let info, info.item.isDirectory else { return }
        let total = await info.withTotal(root: root)
        if !Task.isCancelled { deliver(total) }
    }
}

/// Info: a header with the item's icon, name, type and size, a card with the
/// other fields, and a link to Extended. Used as list rows by an item's More
/// screen, Folder Info and the file placeholder.
struct InfoView: View {
    let info: LoadedInfo
    /// A line under the header, such as the placeholder's "No viewer yet".
    var note: LocalizedStringResource?

    @AppStorage(FileSettings.showExtensionsKey) private var showExtensions =
        FileSettings.showExtensionsDefault
    @AppStorage(FileSettings.dateStyleKey) private var dateStyle = FileSettings.dateStyleDefault
    @AppStorage(FileSettings.use24HourKey) private var use24Hour = FileSettings.use24HourDefault

    var body: some View {
        header
            .listRowBackground(Color.clear)
        card
        // A link, so it also works in the file placeholder's navigation stack.
        NavigationLink(value: Route.extendedInfo(info.item.path)) {
            Text("Extended")
        }
    }

    private var name: String {
        if info.item.path == .root { return String(localized: "Files") }
        return info.item.displayName(showExtensions: showExtensions)
    }

    private var header: some View {
        return InfoHeader(
            kind: info.item.kind, name: name,
            summary: FileInfo.summary(for: info.item, size: info.size), note: note)
    }

    private var card: some View {
        let fields = FileInfo.cardFields(
            FileInfo.fields(
                for: info.item, size: info.size, itemCount: info.itemCount,
                date: {
                    DateDisplay.string(
                        for: $0, now: Date(), relative: false, style: dateStyle,
                        use24Hour: use24Hour)
                }))
        return InfoCard(fields: fields.map { ($0.label.title, $0.value) })
    }
}

/// Info's header: the item's icon, name, and type and size.
struct InfoHeader: View {
    let kind: FileKind
    let name: String
    let summary: String
    var note: LocalizedStringResource?

    var body: some View {
        VStack(spacing: 4) {
            FileIcon(kind: kind)
                .font(.largeTitle)
            Text(verbatim: name)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(verbatim: summary)
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
    }
}

/// Info's card: one list row holding every field, label on the left and value
/// on the right, with hairlines between them.
struct InfoCard: View {
    let fields: [(label: LocalizedStringResource, value: String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                if index > 0 {
                    Divider()
                }
                // Side by side when they fit; otherwise the value goes beneath its label, so it
                // doesn't break a letter at a time.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(field.label)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                        Text(verbatim: field.value)
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.label)
                            .foregroundStyle(.secondary)
                        Text(verbatim: field.value)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
                .padding(.vertical, 5)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Shown where an item's information was expected but the item has gone.
struct MissingItem: View {
    var body: some View {
        Text("This item no longer exists")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .listRowBackground(Color.clear)
    }
}

/// A folder's More › Folder Info: Info with the count of its items.
struct FolderInfoScreen: View {
    let path: FilePath

    @State private var info: LoadedInfo?
    @State private var loaded = false

    var body: some View {
        List {
            if let info {
                InfoView(info: info)
            } else if loaded {
                MissingItem()
            }
        }
        .navigationTitle("Folder Info")
        .task {
            await LoadedInfo.load(path, countsItems: true) {
                info = $0
                loaded = true
            }
        }
    }
}

/// Info › Extended: the POSIX permissions and what they mean, the owner and
/// group, and the extended attributes, including Dialect's view settings.
struct ExtendedInfoScreen: View {
    let path: FilePath

    @State private var info: ExtendedInfo?
    @State private var loaded = false

    var body: some View {
        List {
            if let info {
                Section("Permissions") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: info.permissions)
                            .font(.body.monospaced())
                        ForEach(info.access, id: \.self) { line in
                            Text(verbatim: line)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Section {
                    row("Owner", info.owner)
                    row("Group", info.group)
                }
                Section("Extended Attributes") {
                    if info.attributes.isEmpty {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(info.attributes, id: \.name) { attribute in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: attribute.name)
                            Text(
                                verbatim: ByteCountFormatter.string(
                                    fromByteCount: Int64(attribute.size), countStyle: .file)
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else if loaded {
                MissingItem()
            }
        }
        .navigationTitle("Extended")
        .task {
            let url = path.url(in: FilesRoot.url)
            info = await Task.detached { FileInfo.extended(at: url) }.value
            loaded = true
        }
    }

    private func row(_ label: LocalizedStringResource, _ value: String) -> some View {
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
