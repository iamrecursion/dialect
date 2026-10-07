import SwiftUI

/// What the clipboard holds, with Paste and Move into the folder it was opened
/// from, and Clear Clipboard.
struct ClipboardScreen: View {
    let folder: FilePath

    @Environment(Navigation.self) private var navigation
    @AppStorage(FileSettings.showExtensionsKey) private var showExtensions =
        FileSettings.showExtensionsDefault

    /// `nil` until the first read finishes.
    @State private var items: [FileItem]?
    @State private var transfer: TransferRequest?
    @State private var clearing = false
    @State private var failure: OperationFailure?

    var body: some View {
        List {
            if let items {
                if let first = items.first {
                    Section {
                        ForEach(items) { item in
                            ClipboardRow(item: item, showExtensions: showExtensions)
                        }
                    } header: {
                        Text(verbatim: Self.heading(for: first.path.parent ?? .root))
                    }
                } else {
                    Text("The clipboard is empty")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .listRowBackground(Color.clear)
                }
                actions(isEmpty: items.isEmpty)
            }
        }
        .navigationTitle("Clipboard")
        // Reads again each time it's back on top.
        .task(id: isOnTop) {
            if isOnTop { await load() }
        }
        .clipboardTransfer($transfer) { navigation.pop(to: folderRoute) }
        .operationFailureAlert($failure)
    }

    @ViewBuilder private func actions(isEmpty: Bool) -> some View {
        // Select mode isn't built yet.
        Section {
            Button {
            } label: {
                MenuRowLabel(title: "Select", systemImage: "checkmark.circle.badge.plus")
            }
            Button {
            } label: {
                MenuRowLabel(title: "Copy", systemImage: ClipboardSymbol.copy)
            }
        }
        .disabled(true)
        Section {
            Button {
                transfer = TransferRequest(kind: .paste, folder: folder)
            } label: {
                MenuRowLabel(title: "Paste", systemImage: ClipboardSymbol.paste)
            }
            Button {
                transfer = TransferRequest(kind: .move, folder: folder)
            } label: {
                MenuRowLabel(title: "Move", systemImage: ClipboardSymbol.move)
            }
        }
        .disabled(isEmpty || transfer != nil)
        Section {
            Button(action: clear) {
                MenuRowLabel(title: "Clear Clipboard", systemImage: ClipboardSymbol.clear)
            }
        }
        .disabled(isEmpty || clearing)
    }

    /// Where the items are: "In /notes", or "In Files" at the root.
    nonisolated static func heading(for folder: FilePath) -> String {
        return folder == .root
            ? String(localized: "In Files") : String(localized: "In \(folder.display)")
    }

    private var folderRoute: Route { Route.folderRoute(for: folder) }

    private var isOnTop: Bool { navigation.path.last == .clipboard(folder) }

    private func load() async {
        let clipboard = FilesRoot.operations.clipboard
        let root = FilesRoot.url
        let textExtensions = FileSettings.textExtensions()
        items = await Task.detached(priority: .userInitiated) {
            clipboard.items(root: root, textExtensions: textExtensions)
        }.value
    }

    /// Empties the clipboard and goes back to the folder.
    private func clear() {
        guard !clearing else { return }
        clearing = true
        Task {
            defer { clearing = false }
            do {
                try await FilesRoot.operations.clearClipboard()
                navigation.pop(to: folderRoute)
            } catch {
                failure = OperationFailure("Couldn't Clear", error)
            }
        }
    }
}

/// An item on the clipboard: its icon and name. It isn't tappable; it says what
/// Paste and Move will take.
private struct ClipboardRow: View {
    let item: FileItem
    let showExtensions: Bool

    /// As `FileRow`'s, so the clipboard lines up with folders.
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 30

    private var name: String { item.displayName(showExtensions: showExtensions) }

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(kind: item.kind)
                .font(.title3)
                .frame(width: iconWidth)
            Text(verbatim: name)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(item.kind.typeName))
    }
}
