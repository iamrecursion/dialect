import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// What Share sends: a file, a folder, a session or several items as a zip.
enum Shared: Equatable, Sendable {
    case file(FilePath)
    case archive([FilePath], name: String)

    /// A single file is sent as itself, a single folder or session as
    /// `name.zip`, and several items as `Archive.zip`; `nil` for nothing.
    static func of(_ paths: [FilePath], isDirectory: (FilePath) -> Bool) -> Shared? {
        guard let first = paths.first, let name = first.name else { return nil }
        guard paths.count == 1 else { return .archive(paths, name: "Archive.zip") }
        return isDirectory(first) ? .archive(paths, name: archiveName(of: first)) : .file(first)
    }

    /// A folder's or session's zip: `name.zip`.
    static func archiveName(of folder: FilePath) -> String {
        return "\(folder.name ?? "Files").zip"
    }

    /// The name it's sent under.
    var name: String {
        switch self {
        case .file(let path): return path.name ?? ""
        case .archive(_, let name): return name
        }
    }
}

enum SharingError: LocalizedError, Equatable {
    /// The item holds Dialect's own files, such as a link to a folder around
    /// them.
    case holdsDialect(String)

    var errorDescription: String? {
        switch self {
        case .holdsDialect(let name):
            return String(
                localized: "\(name) can't be shared, as Dialect's own files are inside it.")
        }
    }
}

/// Preparing what Share sends, in `Sharing` among Files' stores.
enum Sharing {
    /// Empties the `Sharing` folder.
    static func clear(in stores: URL) {
        try? FileManager.default.removeItem(at: FilesStores.sharing(in: stores))
    }

    /// The file to send for a shared file: itself, or a clone of what it leads
    /// to under its own name when it's a link.
    static func file(_ path: FilePath, root: URL, stores: URL) throws -> URL {
        clear(in: stores)
        let url = path.url(in: root)
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink == true, let name = path.name else { return url }
        let destination = try newFolder(in: stores).appending(path: name)
        try gather(url, into: destination)
        return destination
    }

    /// Zips the items: one under its own name, several inside `Archive`.
    static func zip(_ paths: [FilePath], name: String, root: URL, stores: URL) throws -> URL {
        clear(in: stores)
        let folder = try newFolder(in: stores)
        let top: URL
        if paths.count == 1, let only = paths.first?.name {
            top = folder.appending(path: only, directoryHint: .isDirectory)
            try gather(paths[0].url(in: root), into: top)
        } else {
            top = folder.appending(path: "Archive", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: top, withIntermediateDirectories: false)
            // A link leading nowhere is left out, as inside a folder.
            let items = paths.filter {
                FileManager.default.fileExists(atPath: $0.url(in: root).path(percentEncoded: false))
            }
            let shared = items.map { $0.url(in: root) }
            for path in items {
                guard let name = path.name else { continue }
                try gather(
                    path.url(in: root), into: top.appending(path: name), sharedWith: shared)
            }
        }
        let zip = folder.appending(path: name, directoryHint: .notDirectory)
        try zipFolder(top, to: zip)
        try? FileManager.default.removeItem(at: top)
        return zip
    }

    /// Copies `item` to `destination`, cloning files, and replacing links with
    /// what it leads to.
    static func gather(_ item: URL, into destination: URL, sharedWith shared: [URL] = [])
        throws
    {
        let real = item.resolvingSymlinksInPath()
        let into = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        guard !into.pathComponents.starts(with: real.pathComponents) else {
            throw SharingError.holdsDialect(item.lastPathComponent)
        }
        let within =
            [real.pathComponents] + shared.map { $0.resolvingSymlinksInPath().pathComponents }
        try copy(real, to: destination, within: within, walking: [])
    }

    /// Copies `url`, which isn't a link, to `destination`. `walking` holds the
    /// folders it's inside, as reached.
    private static func copy(
        _ url: URL, to destination: URL, within items: [[String]], walking: [[String]]
    ) throws {
        let manager = FileManager.default
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        guard values.isDirectory == true else {
            if values.isRegularFile == true {
                try manager.copyItem(at: url, to: destination)
            }
            return
        }
        try manager.createDirectory(at: destination, withIntermediateDirectories: false)
        let walking = walking + [url.pathComponents]
        let children = try manager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isSymbolicLinkKey])
        for child in children {
            var source = child
            if try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                let target = child.resolvingSymlinksInPath()
                let components = target.pathComponents
                guard manager.fileExists(atPath: target.path(percentEncoded: false)),
                    items.contains(where: { components.starts(with: $0) }),
                    !walking.contains(where: { $0.starts(with: components) })
                else { continue }
                source = target
            }
            try copy(
                source, to: destination.appending(path: child.lastPathComponent), within: items,
                walking: walking)
        }
    }

    /// A new folder in `Sharing` for one share.
    private static func newFolder(in stores: URL) throws -> URL {
        let folder = FilesStores.sharing(in: stores).appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The system's zip of `folder`, with the folder at its top. The system
    /// removes its zip once the block returns, so it's moved out first.
    private static func zipFolder(_ folder: URL, to destination: URL) throws {
        var coordinatorError: NSError?
        var moveError: Error?
        NSFileCoordinator().coordinate(
            readingItemAt: folder, options: .forUploading, error: &coordinatorError
        ) { zipped in
            do {
                try FileManager.default.moveItem(at: zipped, to: destination)
            } catch {
                moveError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let moveError { throw moveError }
    }
}

/// A file as Share sends it: as plain data, so Mail attaches it under its name.
struct SharedFile: Transferable {
    let path: FilePath
    let root: URL
    let stores: URL
    let sent: @MainActor @Sendable () -> Void

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { file in
            await file.sent()
            return SentTransferredFile(
                try Sharing.file(file.path, root: file.root, stores: file.stores))
        }
        .suggestedFileName { $0.path.name }
    }
}

/// Items zipped as Share sends them, when the receiving app asks, so a canceled
/// share zips nothing.
struct SharedArchive: Transferable {
    let paths: [FilePath]
    let name: String
    let root: URL
    let stores: URL
    let sent: @MainActor @Sendable () -> Void

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { archive in
            await archive.sent()
            return SentTransferredFile(
                try Sharing.zip(
                    archive.paths, name: archive.name, root: archive.root, stores: archive.stores))
        }
        .suggestedFileName { $0.name }
    }
}

/// More's Share row, which opens the share sheet.
struct ShareRow: View {
    let shared: Shared

    /// Called as the receiving app takes it, which a canceled share never does.
    var sent: @MainActor @Sendable () -> Void = {}

    var body: some View {
        switch shared {
        case .file(let path):
            ShareLink(
                item: SharedFile(
                    path: path, root: FilesRoot.url, stores: FilesStores.url, sent: sent),
                preview: SharePreview(shared.name)
            ) {
                label
            }
        case .archive(let paths, let name):
            ShareLink(
                item: SharedArchive(
                    paths: paths, name: name, root: FilesRoot.url, stores: FilesStores.url,
                    sent: sent),
                preview: SharePreview(name)
            ) {
                label
            }
        }
    }

    private var label: some View {
        return MenuRowLabel(title: "Share", systemImage: ShareSymbol.share)
    }
}

enum ShareSymbol {
    static let share = "square.and.arrow.up"
}
