import Foundation
import Synchronization

/// Text-like checks made after a folder is listed, kept so a folder read again,
/// lists what's known at once. A result holds while the file's size and
/// modification date do.
///
/// A lock rather than an actor, as the (non-async) listing reads it.
final class FileKinds: Sendable {
    static let shared = FileKinds()

    private struct Entry {
        let size: Int64?
        let modified: Date?
        let kind: FileKind
    }

    /// By the path as browsed: a listing through a link sees the target's URLs.
    private let cache = Mutex<[FilePath: Entry]>([:])

    /// The kind found before, if the file hasn't changed since.
    func cached(_ path: FilePath, size: Int64?, modified: Date?) -> FileKind? {
        return cache.withLock { cache in
            guard let entry = cache[path], entry.size == size, entry.modified == modified
            else { return nil }
            return entry.kind
        }
    }

    /// Reads the start of the item's file, so it's called off the main actor.
    /// Something no longer a regular file, such as a pipe put in its place
    /// since the listing, is binary and never opened.
    func check(_ item: FileItem, root: URL) -> FileKind {
        let url = item.path.url(in: root)
        let isFile =
            (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]))?
            .isRegularFile == true
        let kind = isFile ? FileKind.sniff(url) : .binary
        cache.withLock {
            $0[item.path] = Entry(size: item.size, modified: item.modified, kind: kind)
        }
        return kind
    }
}
