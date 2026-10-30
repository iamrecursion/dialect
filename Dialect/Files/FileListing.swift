import Foundation

/// Reading folders and items from disk, called off the main actor.
enum FileListing {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey,
        .contentModificationDateKey, .isWritableKey,
    ]

    /// A folder's items, unsorted, without the inbox. Dotfiles are left out
    /// unless `showHidden`. Throws when the folder can't be read, such as when
    /// it's gone.
    ///
    /// With `checking`, a file whose extension Files doesn't know takes the
    /// kind found before, or is listed unchecked, to be checked afterward.
    /// Without, it's checked here.
    static func items(
        in folder: FilePath, root: URL, showHidden: Bool, textExtensions: Set<String>,
        checking kinds: FileKinds? = nil
    ) throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder.url(in: root).resolvingSymlinksInPath(),
            includingPropertiesForKeys: Array(keys))
        return urls.compactMap { url in
            let name = url.lastPathComponent
            let path = folder.appending(name)
            guard path != .inbox, showHidden || !name.hasPrefix(".") else { return nil }
            return item(path: path, url: url, textExtensions: textExtensions, kinds: kinds)
        }
    }

    /// One item, such as for its More screen. Throws when it's missing.
    static func item(at path: FilePath, root: URL, textExtensions: Set<String>) throws -> FileItem {
        let url = path.url(in: root)
        // Doesn't follow a final symbolic link, so a broken one is still found.
        _ = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return item(path: path, url: url, textExtensions: textExtensions)
    }

    /// An item whose attributes can't be read, such as a broken symbolic link,
    /// is listed as a binary file with nothing known about it.
    private static func item(
        path: FilePath, url: URL, textExtensions: Set<String>, kinds: FileKinds? = nil
    ) -> FileItem {
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
        let size = isDirectory ? nil : values.fileSize.map(Int64.init)
        let modified = values.contentModificationDate
        var kind: FileKind
        var needsCheck = false
        if isDirectory || values.isRegularFile == true {
            if let known = FileKind.classify(
                name: path.name ?? "", isDirectory: isDirectory, textExtensions: textExtensions)
            {
                kind = known
            } else if let kinds {
                let cached = kinds.cached(path, size: size, modified: modified)
                kind = cached ?? .otherText
                needsCheck = cached == nil
            } else {
                kind = FileKind.sniff(url)
            }
        } else {
            // A pipe, socket or device: never opened, as opening a pipe waits for a writer.
            kind = .binary
        }
        var item = FileItem(
            path: path, kind: kind, isDirectory: isDirectory, size: size,
            created: values.creationDate, modified: modified,
            isReadOnly: values.isWritable == false)
        item.needsCheck = needsCheck
        return item
    }
}
