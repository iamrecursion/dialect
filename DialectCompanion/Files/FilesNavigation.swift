import Observation

/// Where Files can go from Browse.
enum FilesDestination: Hashable {
    case folder(FilePath)
    case session(FilePath)
    case trash
}

/// The Files tab's stack.
@MainActor @Observable
final class FilesNavigation {
    var path: [FilesDestination] = []

    /// Shows `folder`, over each folder from the root down to it.
    func show(_ folder: FilePath) {
        path = (folder.ancestors + [folder]).map { .folder($0) }
    }
}
