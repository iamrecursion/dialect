import SwiftUI

/// The watch's files.
struct FilesTab: View {
    @Environment(WatchFiles.self) private var files
    @State private var navigation = FilesNavigation()

    var body: some View {
        NavigationStack(path: $navigation.path) {
            BrowseScreen(model: RecentsModel(files: files))
                .navigationDestination(for: FilesDestination.self) { destination in
                    switch destination {
                    case .folder(let path):
                        FolderListScreen(model: FolderModel(path: path, files: files))
                    case .session(let path):
                        PlaceholderScreen(
                            verbatim: FileItem.displayName(
                                of: path.name ?? "",
                                showExtensions: files.link.display.showExtensions))
                    case .trash:
                        TrashScreen(model: BinModel(files: files))
                    }
                }
        }
        .environment(navigation)
    }
}
