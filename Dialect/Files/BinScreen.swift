import SwiftUI

/// A bin item with its icon.
struct BinEntry: Identifiable, Hashable, Sendable {
    let item: BinItem
    let kind: FileKind

    var id: UUID { item.id }

    /// The bin's items, newest deletion first, with their kinds.
    static func load(_ bin: Bin, textExtensions: Set<String>) -> [BinEntry] {
        return bin.items().map { BinEntry($0, textExtensions: textExtensions) }
    }

    init(_ item: BinItem, textExtensions: Set<String>) {
        self.item = item
        self.kind =
            FileKind.classify(
                name: item.name, isDirectory: item.isDirectory, textExtensions: textExtensions)
            ?? FileKind.sniff(item.url)
    }

    /// The row's lines beneath the name: "Deleted *when*", then the days left
    /// when the bin empties itself.
    static func detail(
        for item: BinItem, now: Date, relative: Bool, style: DateStyle, use24Hour: Bool,
        emptyAfter days: Int?
    ) -> [String] {
        let when = DateDisplay.string(
            for: item.deleted, now: now, relative: relative, style: style, use24Hour: use24Hour,
            startsSentence: false)
        let deleted = String(localized: "Deleted \(when)")
        guard let left = item.daysLeft(now: now, after: days) else { return [deleted] }
        return [deleted, daysLeft(left)]
    }

    static func daysLeft(_ days: Int) -> String {
        return days == 1
            ? String(localized: "1 day left") : String(localized: "\(days) days left")
    }
}

/// The bin's icons.
enum BinSymbol {
    static let restore = "checkmark.arrow.trianglehead.counterclockwise"
}

/// The bin: what's been deleted, newest first. A tap shows an item's
/// information and swipes can restore it or delete it for good.
struct BinScreen: View {
    /// Select is disabled until select mode exists.
    static let buttons = [
        MenuItem(
            title: "Select", systemImage: "checkmark.circle.badge.plus", route: .bin,
            isDisabled: true),
        MenuItem(title: "More", systemImage: "ellipsis.circle", route: .binMore),
    ]

    @Environment(Navigation.self) private var navigation
    @Environment(\.dialectAccent) private var accent
    @AppStorage(FileSettings.relativeModifiedKey) private var relativeModified =
        FileSettings.relativeModifiedDefault
    @AppStorage(FileSettings.dateStyleKey) private var dateStyle = FileSettings.dateStyleDefault
    @AppStorage(FileSettings.use24HourKey) private var use24Hour = FileSettings.use24HourDefault
    @AppStorage(FileSettings.emptyTrashAfterKey) private var emptyTrashAfter =
        FileSettings.emptyTrashAfterDefault

    /// `nil` until the first read finishes.
    @State private var entries: [BinEntry]?

    /// Items being restored or deleted, whose rows leave at once.
    @State private var leaving: Set<UUID> = []
    @State private var confirming: BinEntry?
    @State private var note: String?
    @State private var failure: OperationFailure?

    /// Counts reads begun, so one overtaken by a newer is dropped.
    @State private var reads = 0

    var body: some View {
        ActionList(actions: Self.buttons, perform: { navigation.push($0.route) }) {
            rows
        }
        .navigationTitle("Trash")
        // Reads again each time it's back on top.
        .task(id: isOnTop) {
            if isOnTop { await load() }
        }
        .confirmationDialog(
            Text(verbatim: confirming.map(Self.deletePermanentlyTitle) ?? ""),
            isPresented: Binding(
                get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible, presenting: confirming
        ) { entry in
            Button("Delete Permanently", role: .destructive) { deletePermanently(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
        .alert(
            "Restored",
            isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } }),
            actions: { Button("OK") {} },
            message: { Text(verbatim: note ?? "") }
        )
        .operationFailureAlert($failure)
    }

    nonisolated static func deletePermanentlyTitle(_ entry: BinEntry) -> String {
        return String(localized: "Delete “\(entry.item.name)” permanently?")
    }

    private var isOnTop: Bool { navigation.path.last == .bin }

    @ViewBuilder private var rows: some View {
        if let entries {
            let shown = entries.filter { !leaving.contains($0.id) }
            if shown.isEmpty {
                Text("The Trash is empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .listRowBackground(Color.clear)
            }
            let now = Date()
            ForEach(shown) { entry in
                BinRow(
                    entry: entry,
                    detail: BinEntry.detail(
                        for: entry.item, now: now, relative: relativeModified, style: dateStyle,
                        use24Hour: use24Hour,
                        emptyAfter: emptyTrashAfter > 0 ? emptyTrashAfter : nil)
                ) {
                    navigation.push(.binItem(entry.id))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        confirming = entry
                    } label: {
                        Label {
                            Text("Delete Permanently")
                        } icon: {
                            FileSymbol.deletePermanently.image
                        }
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        restore(entry)
                    } label: {
                        Label("Restore", systemImage: BinSymbol.restore)
                    }
                    .tint(accent)
                }
                .accessibilityAction(named: Text("Restore")) { restore(entry) }
                .accessibilityAction(named: Text("Delete Permanently")) { confirming = entry }
            }
        }
    }

    /// Removes what's expired, then reads the bin off the main actor.
    private func load() async {
        reads += 1
        let read = reads
        let operations = FilesRoot.operations
        await operations.removeExpired(after: FileSettings.emptyTrashAfter())
        let bin = operations.bin
        let textExtensions = FileSettings.textExtensions()
        let loaded = await Task.detached(priority: .userInitiated) {
            BinEntry.load(bin, textExtensions: textExtensions)
        }.value
        guard !Task.isCancelled, read == reads else { return }
        entries = loaded
    }

    private func restore(_ entry: BinEntry) {
        leaving.insert(entry.id)
        Task {
            do {
                note = try await FilesRoot.operations.restore(entry.item).note
            } catch {
                failure = OperationFailure("Couldn't Restore", error)
            }
            await load()
            leaving.remove(entry.id)
        }
    }

    private func deletePermanently(_ entry: BinEntry) {
        leaving.insert(entry.id)
        Task {
            do {
                try await FilesRoot.operations.deletePermanently([entry.item])
            } catch {
                failure = OperationFailure("Couldn't Delete", error)
            }
            await load()
            leaving.remove(entry.id)
        }
    }
}

/// One bin item: its icon, its name in the bin, and when it was deleted.
private struct BinRow: View {
    let entry: BinEntry
    let detail: [String]
    let open: () -> Void

    /// As `FileRow`'s, so the bin lines up with folders.
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 30

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                FileIcon(kind: entry.kind)
                    .font(.title3)
                    .frame(width: iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.item.name)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    ForEach(detail, id: \.self) { line in
                        Text(verbatim: line)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityLabel(Text(verbatim: entry.item.name))
        .accessibilityValue(Text(verbatim: detail.joined(separator: ", ")))
    }
}

/// A bin item's information: Info's header, then where it was, when it was
/// deleted and the days it has left, then Restore and Delete Permanently for
/// those who don't swipe.
struct BinItemScreen: View {
    let id: UUID

    @Environment(Navigation.self) private var navigation
    @AppStorage(FileSettings.dateStyleKey) private var dateStyle = FileSettings.dateStyleDefault
    @AppStorage(FileSettings.use24HourKey) private var use24Hour = FileSettings.use24HourDefault
    @AppStorage(FileSettings.emptyTrashAfterKey) private var emptyTrashAfter =
        FileSettings.emptyTrashAfterDefault

    @State private var entry: BinEntry?
    @State private var size: Int64?
    @State private var loaded = false
    @State private var confirming = false
    @State private var note: String?
    @State private var failure: OperationFailure?
    /// Set while Restore or Delete Permanently runs, so a second tap does
    /// nothing.
    @State private var working = false

    var body: some View {
        List {
            if let entry {
                InfoHeader(
                    kind: entry.kind, name: entry.item.name,
                    summary:
                        "\(String(localized: entry.kind.typeName)) · \(SizeDisplay.string(size))"
                )
                .listRowBackground(Color.clear)
                InfoCard(fields: fields(entry.item))
                Section {
                    Button(action: restore) {
                        MenuRowLabel(title: "Restore", systemImage: BinSymbol.restore)
                    }
                    Button {
                        confirming = true
                    } label: {
                        MenuRowLabel(title: "Delete Permanently", symbol: .deletePermanently)
                    }
                }
                .disabled(working)
            } else if loaded {
                MissingItem()
            }
        }
        .navigationTitle("Info")
        .task { await load() }
        .confirmationDialog(
            Text(verbatim: entry.map(BinScreen.deletePermanentlyTitle) ?? ""),
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive, action: deletePermanently)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            "Restored",
            isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } }),
            actions: { Button("OK") { navigation.pop(to: .bin) } },
            message: { Text(verbatim: note ?? "") }
        )
        .operationFailureAlert($failure)
    }

    private func fields(_ item: BinItem) -> [(label: LocalizedStringResource, value: String)] {
        let deleted = DateDisplay.string(
            for: item.deleted, now: Date(), relative: false, style: dateStyle,
            use24Hour: use24Hour)
        var fields: [(label: LocalizedStringResource, value: String)] = [
            // The folder, as the name it goes back under may have changed in the bin.
            ("Original Location", (item.original.parent ?? .root).display), ("Deleted", deleted),
        ]
        let days = emptyTrashAfter > 0 ? emptyTrashAfter : nil
        if let left = item.daysLeft(now: Date(), after: days) {
            fields.append(("Days Left", left.formatted()))
        }
        return fields
    }

    /// Reads the item, then its size: a folder's or session's total takes a
    /// walk.
    private func load() async {
        let bin = FilesRoot.operations.bin
        let textExtensions = FileSettings.textExtensions()
        let id = id
        let found = await Task.detached {
            bin.item(id).map { BinEntry($0, textExtensions: textExtensions) }
        }.value
        entry = found
        loaded = true
        guard let item = found?.item else { return }
        size = await Task.detached(priority: .utility) {
            if item.isDirectory { return FolderSizes.total(of: item.url) }
            let values = try? item.url.resourceValues(forKeys: [.fileSizeKey])
            return values?.fileSize.map(Int64.init)
        }.value
    }

    private func restore() {
        guard let entry, !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let restored = try await FilesRoot.operations.restore(entry.item)
                if let message = restored.note {
                    note = message
                } else {
                    navigation.pop(to: .bin)
                }
            } catch {
                failure = OperationFailure("Couldn't Restore", error)
            }
        }
    }

    private func deletePermanently() {
        guard let entry, !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await FilesRoot.operations.deletePermanently([entry.item])
                navigation.pop(to: .bin)
            } catch {
                failure = OperationFailure("Couldn't Delete", error)
            }
        }
    }
}

/// The bin's More: Restore All and Delete All, which act and go back.
struct BinMoreScreen: View {
    @Environment(Navigation.self) private var navigation

    /// How many items are in the bin, read as the screen appears.
    @State private var count: Int?
    @State private var confirming = false
    @State private var note: String?
    @State private var failure: OperationFailure?
    /// Set while Restore All or Delete All runs, so a second tap does nothing.
    @State private var working = false

    var body: some View {
        List {
            Section {
                Button(action: restoreAll) {
                    MenuRowLabel(title: "Restore All", systemImage: BinSymbol.restore)
                }
                Button {
                    confirming = true
                } label: {
                    MenuRowLabel(title: "Delete All", symbol: .deletePermanently)
                }
            }
            .disabled(count == 0 || working)
        }
        .navigationTitle("More")
        .task {
            let bin = FilesRoot.operations.bin
            count = await Task.detached { bin.items().count }.value
        }
        .confirmationDialog(
            Text(verbatim: Self.deleteAllTitle(count ?? 0)), isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive, action: deleteAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            "Restored",
            isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } }),
            actions: { Button("OK") { navigation.pop(to: .bin) } },
            message: { Text(verbatim: note ?? "") }
        )
        .operationFailureAlert($failure)
    }

    nonisolated static func deleteAllTitle(_ count: Int) -> String {
        return count == 1
            ? String(localized: "Delete 1 item permanently?")
            : String(localized: "Delete all \(count) items permanently?")
    }

    /// What Restore All's alert says when some came back dated; `nil` when none
    /// did.
    nonisolated static func restoreAllNote(dated: Int) -> String? {
        switch dated {
        case 0: return nil
        case 1:
            return String(
                localized:
                    "1 item came back with its deletion date added, as something in Files now has its name."
            )
        default:
            return String(
                localized:
                    "\(dated) items came back with their deletion dates added, as something in Files now has their names."
            )
        }
    }

    private func restoreAll() {
        guard !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let restored = try await FilesRoot.operations.restoreAll()
                if let message = Self.restoreAllNote(
                    dated: restored.filter { !$0.isWhereItWas }.count)
                {
                    note = message
                } else {
                    navigation.pop(to: .bin)
                }
            } catch let partial as PartialFailure<Restored> {
                // Say how far it got.
                failure = OperationFailure(
                    "Couldn't Restore",
                    reason: Self.stoppedNote(
                        restored: partial.done.count,
                        dated: partial.done.filter { !$0.isWhereItWas }.count,
                        reason: partial.underlying.localizedDescription))
            } catch {
                failure = OperationFailure("Couldn't Restore", error)
            }
        }
    }

    /// What Restore All says when it stops part way: how many it restored, how
    /// many of those are dated, and why it stopped.
    nonisolated static func stoppedNote(restored: Int, dated: Int, reason: String) -> String {
        let done =
            restored == 1
            ? String(localized: "1 item was restored before Restore All stopped.")
            : String(localized: "\(restored) items were restored before Restore All stopped.")
        let dates = restoreAllNote(dated: dated).map { " \($0)" } ?? ""
        return "\(done)\(dates) \(reason)"
    }

    private func deleteAll() {
        guard !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await FilesRoot.operations.deleteAll()
                navigation.pop(to: .bin)
            } catch {
                failure = OperationFailure("Couldn't Delete", error)
            }
        }
    }
}
