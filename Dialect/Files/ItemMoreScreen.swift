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

    var body: some View {
        List {
            if let info {
                InfoView(info: info)
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
        .task {
            await LoadedInfo.load(path, countsItems: false) {
                info = $0
                loaded = true
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
