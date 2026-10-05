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

    var id: FilePath { path }

    /// The full name, with its extension; empty at the root.
    var name: String { path.name ?? "" }

    /// A leading dot hides an item, as on macOS.
    var isHidden: Bool { name.hasPrefix(".") }

    /// The name without its extension.
    var baseName: String { pathExtension.isEmpty ? name : Self.splitName(name).base }

    /// Empty for folders, whose names are never split; `dial` for sessions.
    var pathExtension: String { kind == .folder ? "" : Self.splitName(name).ext }

    /// The name as rows show it: with its extension when Show File Extensions
    /// is on. Folders show their whole name either way.
    func displayName(showExtensions: Bool) -> String {
        return showExtensions ? name : baseName
    }

    /// Splits at the last dot, as the Finder does, except a leading or trailing
    /// dot, which starts no extension.
    static func splitName(_ name: String) -> (base: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex,
            name.index(after: dot) != name.endIndex
        else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }
}

/// Reading folders and items from disk. Called off the main actor.
enum FileListing {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey,
        .contentModificationDateKey, .isWritableKey,
    ]

    /// A folder's items, unsorted. Dotfiles are left out unless `showHidden`.
    /// Throws when the folder can't be read, such as when it's gone.
    static func items(
        in folder: FilePath, root: URL, showHidden: Bool, textExtensions: Set<String>
    ) throws -> [FileItem] {
        // Resolved, as listing a link to a folder fails with "Not a directory".
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder.url(in: root).resolvingSymlinksInPath(),
            includingPropertiesForKeys: Array(keys))
        return urls.compactMap { url in
            let name = url.lastPathComponent
            guard showHidden || !name.hasPrefix(".") else { return nil }
            return item(path: folder.appending(name), url: url, textExtensions: textExtensions)
        }
    }

    /// One item, such as for its More screen. Throws when it's gone.
    static func item(at path: FilePath, root: URL, textExtensions: Set<String>) throws -> FileItem {
        let url = path.url(in: root)
        // Doesn't follow a final symbolic link, so a broken one is still found.
        _ = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return item(path: path, url: url, textExtensions: textExtensions)
    }

    /// An item whose attributes can't be read, such as a broken symbolic link,
    /// is listed as a binary file with nothing known about it.
    private static func item(path: FilePath, url: URL, textExtensions: Set<String>) -> FileItem {
        var values = try? url.resourceValues(forKeys: keys)
        if values?.isSymbolicLink == true {
            // A link is shown as what it leads to.
            let target = url.resolvingSymlinksInPath()
            values =
                FileManager.default.fileExists(atPath: target.path(percentEncoded: false))
                ? try? target.resourceValues(forKeys: keys) : nil
        }
        guard let values else {
            return FileItem(
                path: path, kind: .binary, isDirectory: false, size: nil, created: nil,
                modified: nil, isReadOnly: false)
        }
        let isDirectory = values.isDirectory ?? false
        let kind: FileKind
        if isDirectory || values.isRegularFile == true {
            kind =
                FileKind.classify(
                    name: path.name ?? "", isDirectory: isDirectory, textExtensions: textExtensions)
                ?? FileKind.sniff(url)
        } else {
            // A pipe, socket or device: never opened, as opening a pipe waits for a writer.
            kind = .binary
        }
        return FileItem(
            path: path, kind: kind, isDirectory: isDirectory,
            size: isDirectory ? nil : values.fileSize.map(Int64.init),
            created: values.creationDate, modified: values.contentModificationDate,
            isReadOnly: values.isWritable == false)
    }
}
