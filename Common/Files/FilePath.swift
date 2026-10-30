import Foundation

/// A place in Files: the names from the root down to an item, so the root has
/// none. Routes carry paths instead of URLs, so a path means the same item
/// whichever root resolves it.
struct FilePath: Hashable, Sendable, Identifiable {
    let components: [String]

    static let root = FilePath(components: [])

    /// The folder WatchConnectivity keeps in `Documents`, which Files leaves
    /// out. It's the system's, so its name can't be used at the root.
    static let inbox = FilePath(components: [inboxName])
    static let inboxName = "Inbox"

    var id: [String] { components }

    /// The item's name, with its extension; `nil` at the root.
    var name: String? { components.last }

    /// The folder holding the item; `nil` at the root.
    var parent: FilePath? {
        return components.isEmpty ? nil : FilePath(components: Array(components.dropLast()))
    }

    /// The folders above the item, from the root down.
    var ancestors: [FilePath] {
        return components.indices.map { FilePath(components: Array(components[..<$0])) }
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

extension FilePath: Codable {
    /// Refuses a path that could reach outside the root, so a damaged history
    /// reads as empty.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let components = try container.decode([String].self)
        guard
            components.allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/")
            })
        else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not a path in Files: \(components)")
        }
        self.init(components: components)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(components)
    }
}
