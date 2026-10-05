import Darwin
import Foundation

/// Renaming in one step to avoid concurrent processes overwriting files.
enum AtomicRename {
    /// Renames `from` to `to`, both on the same volume, failing if `to` is
    /// taken.
    ///
    /// Throws a `CocoaError` saying why, with the POSIX error beneath.
    static func rename(_ from: URL, to: URL) throws {
        let failure = from.withUnsafeFileSystemRepresentation { source in
            to.withUnsafeFileSystemRepresentation { destination -> Int32? in
                guard let source, let destination else { return EINVAL }
                let result = renamex_np(source, destination, UInt32(RENAME_EXCL))
                return result == 0 ? nil : errno
            }
        }
        if let failure { throw error(failure, renaming: from, to: to) }
    }

    /// The error `FileManager` would give, so alerts read as the system's do.
    private static func error(_ code: Int32, renaming from: URL, to: URL) -> CocoaError {
        let posix = POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        let (kind, url): (CocoaError.Code, URL) =
            switch posix.code {
            case .EEXIST, .ENOTEMPTY: (.fileWriteFileExists, to)
            case .ENOENT: (.fileNoSuchFile, from)
            case .EACCES, .EPERM: (.fileWriteNoPermission, from)
            case .ENOSPC, .EDQUOT: (.fileWriteOutOfSpace, to)
            case .EROFS: (.fileWriteVolumeReadOnly, to)
            case .ENAMETOOLONG: (.fileWriteInvalidFileName, to)
            default: (.fileWriteUnknown, from)
            }
        return CocoaError(kind, userInfo: [NSURLErrorKey: url, NSUnderlyingErrorKey: posix])
    }
}
