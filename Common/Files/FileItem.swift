import Foundation

/// One item in a folder, as it was when the folder was read.
struct FileItem: Identifiable, Hashable, Sendable {
    let path: FilePath
    let kind: FileKind
    let isDirectory: Bool

    /// A file's size in bytes; `nil` for folders and sessions, whose totals
    /// `FolderSizes` works out, or when it's unreadable.
    let size: Int64?
    let created: Date?
    let modified: Date?
    let isReadOnly: Bool

    /// Listed as a Document until the text-like check, which `FileKinds` makes
    /// after the listing.
    var needsCheck = false

    var id: FilePath { path }

    /// The item with the kind the text-like check found.
    func checked(as kind: FileKind) -> FileItem {
        return FileItem(
            path: path, kind: kind, isDirectory: isDirectory, size: size, created: created,
            modified: modified, isReadOnly: isReadOnly)
    }

    /// The full name, with its extension; empty at the root.
    var name: String { path.name ?? "" }

    /// A leading dot hides an item, as on macOS.
    var isHidden: Bool { name.hasPrefix(".") }

    /// The name without its extension.
    var baseName: String { pathExtension.isEmpty ? name : Self.splitName(name).base }

    /// Empty for folders, whose names are never split; `dial` for sessions.
    var pathExtension: String { kind == .folder ? "" : Self.splitName(name).ext }

    /// The name in rows: with its extension when Show File Extensions is on.
    /// Folders show their whole name either way.
    func displayName(showExtensions: Bool) -> String {
        return showExtensions ? name : baseName
    }

    /// A folder's or entered session's name in rows.
    static func displayName(of name: String, showExtensions: Bool) -> String {
        let kind = FileKind.classify(name: name, isDirectory: true, textExtensions: [])
        return kind == .session && !showExtensions ? splitName(name).base : name
    }

    /// Splits at the last dot, like the Finder, except a leading or trailing
    /// dot, which starts no extension.
    static func splitName(_ name: String) -> (base: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex,
            name.index(after: dot) != name.endIndex
        else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }
}

extension FileItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case path, kind, size, created, modified, isReadOnly
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(FileKind.self, forKey: .kind)
        self.init(
            path: try container.decode(FilePath.self, forKey: .path), kind: kind,
            isDirectory: kind.isDirectory,
            size: try container.decodeIfPresent(Int64.self, forKey: .size),
            created: try container.decodeIfPresent(Date.self, forKey: .created),
            modified: try container.decodeIfPresent(Date.self, forKey: .modified),
            isReadOnly: try container.decode(Bool.self, forKey: .isReadOnly))
    }
}
