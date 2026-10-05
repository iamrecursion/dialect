import SwiftUI

/// What tapping a file opens until it has a viewer: its Info, with "No viewer
/// yet" under the name.
///
/// A cover, so the system's ✕ closes it and it's never on the navigation path.
/// It has its own navigation stack, so Info's Extended row pushes within the
/// cover.
struct FilePlaceholder: View {
    let path: FilePath

    @State private var info: LoadedInfo?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                if let info {
                    InfoView(info: info, note: "No viewer yet")
                } else if loaded {
                    // Deleted since its folder was read.
                    MissingItem()
                } else {
                    // Until the item's read: its name, and what the cover is for.
                    VStack(spacing: 4) {
                        Text(verbatim: path.name ?? "")
                            .font(.headline)
                        Text("No viewer yet")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationDestination(for: Route.self) { $0.destination }
        }
        .task {
            await LoadedInfo.load(path, countsItems: false) {
                info = $0
                loaded = true
            }
        }
    }
}

/// What opening a session shows until the REPL can open one.
struct SessionPlaceholder: View {
    let path: FilePath

    @AppStorage(FileSettings.showExtensionsKey) private var showExtensions =
        FileSettings.showExtensionsDefault

    var body: some View {
        Placeholder(
            verbatim: FolderScreen.displayName(of: path.name ?? "", showExtensions: showExtensions))
    }
}
