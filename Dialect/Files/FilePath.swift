import Foundation

/// A place in Files: the names from the root down to an item, so the root has
/// none. Routes carry paths instead of URLs, so a path means the same item
/// whichever root resolves it.
struct FilePath: Hashable, Sendable, Identifiable {
    let components: [String]

    static let root = FilePath(components: [])

    var id: [String] { components }

    /// The item's name, with its extension; `nil` at the root.
    var name: String? { components.last }

    /// The folder holding the item; `nil` at the root.
    var parent: FilePath? {
        return components.isEmpty ? nil : FilePath(components: Array(components.dropLast()))
    }

    func appending(_ name: String) -> FilePath {
        return FilePath(components: components + [name])
    }

    func url(in root: URL) -> URL {
        return components.reduce(root) { $0.appending(path: $1, directoryHint: .inferFromPath) }
    }

    /// Whether this is `other` or somewhere inside it.
    func isWithin(_ other: FilePath) -> Bool {
        return components.starts(with: other.components)
    }

    /// As Info shows it: `/scripts/prelude.scm`, and `/` at the root.
    var display: String { "/" + components.joined(separator: "/") }
}

/// Where Files' root is: Dialect's `Documents` directory, or the sample tree
/// under `-seedFiles`. Only views read it; everything below them takes the root
/// as a parameter, so tests can use their own.
@MainActor
enum FilesRoot {
    static var url = URL.documentsDirectory
    static var operations = FileOperations(root: url, stores: FilesStores.url)
}
