import SwiftUI

/// An item's More screen.
struct ItemMoreScreen: View {
    let path: FilePath

    @Environment(Navigation.self) private var navigation

    @State private var info: LoadedInfo?
    @State private var loaded = false
    @State private var failure: OperationFailure?

    /// Set while Delete runs, so a second tap does nothing.
    @State private var deleting = false

    /// Whether the clipboard holds anything still there, for Paste and Move.
    @State private var clipboardHolds = false
    @State private var transfer: TransferRequest?

    /// Set while Copy runs, so a second tap doesn't pop twice.
    @State private var copying = false

    var body: some View {
        List {
            if let info {
                InfoView(info: info)
                Section {
                    Button(action: copy) {
                        MenuRowLabel(title: "Copy", systemImage: ClipboardSymbol.copy)
                    }
                    .disabled(copying)
                    if clipboardHolds {
                        Button {
                            transfer = TransferRequest(kind: .paste, folder: destination(info))
                        } label: {
                            MenuRowLabel(title: "Paste", systemImage: ClipboardSymbol.paste)
                        }
                        Button {
                            transfer = TransferRequest(kind: .move, folder: destination(info))
                        } label: {
                            MenuRowLabel(title: "Move", systemImage: ClipboardSymbol.move)
                        }
                    }
                }
                .disabled(transfer != nil)
                Section {
                    // Replaces More, so Back from the name goes to the folder.
                    Button {
                        navigation.replaceTop(with: .rename(path))
                    } label: {
                        MenuRowLabel(
                            title: "Rename", systemImage: "rectangle.and.pencil.and.ellipsis")
                    }
                    Button(action: delete) {
                        MenuRowLabel(title: "Delete", systemImage: "trash")
                    }
                    .disabled(deleting)
                }
                .disabled(transfer != nil)
                if info.item.kind == .session {
                    Section {
                        // Replaces More, so Back from the session goes to its folder.
                        Button {
                            navigation.replaceTop(with: .folder(path))
                        } label: {
                            MenuRowLabel(title: "Enter Session", systemImage: "folder")
                        }
                    }
                }
            } else if loaded {
                MissingItem()
            }
        }
        .navigationTitle("More")
        .operationFailureAlert($failure)
        .clipboardTransfer($transfer) {
            navigation.pop(to: Route.folderRoute(for: path.parent ?? .root))
        }
        .task {
            let clipboard = FilesRoot.operations.clipboard
            let root = FilesRoot.url
            clipboardHolds = await Task.detached {
                !clipboard.existing(root: root).isEmpty
            }.value
            await LoadedInfo.load(path, countsItems: false) {
                info = $0
                loaded = true
            }
        }
    }

    /// Where Paste and Move put things: into a folder, or beside a file or
    /// session.
    private func destination(_ info: LoadedInfo) -> FilePath {
        return info.item.kind == .folder ? path : path.parent ?? .root
    }

    /// Puts the item on the clipboard and leaves More.
    private func copy() {
        guard !copying else { return }
        copying = true
        Task {
            defer { copying = false }
            do {
                try await FileOperations.copyWithTap([path])
                navigation.pop()
            } catch {
                failure = OperationFailure("Couldn't Copy", error)
            }
        }
    }

    /// Deletes the item and leaves More.
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
