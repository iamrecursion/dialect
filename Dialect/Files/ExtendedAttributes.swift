import Darwin
import Foundation

/// One extended attribute, as Info's Extended screen lists it.
struct ExtendedAttribute: Hashable, Sendable {
    let name: String

    /// The value's size in bytes.
    let size: Int
}

/// The Darwin calls for extended attributes. They don't follow a final symbolic
/// link, so a link's attributes are read, not its target's.
enum ExtendedAttributes {
    static func get(_ name: String, at url: URL) -> Data? {
        return url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard size >= 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes {
                getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW)
            }
            return read >= 0 ? data.prefix(read) : nil
        }
    }

    static func set(_ name: String, _ value: Data, at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw POSIXError(.ENOENT) }
            let result = value.withUnsafeBytes {
                setxattr(path, name, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW)
            }
            if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
    }

    static func remove(_ name: String, at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw POSIXError(.ENOENT) }
            if removexattr(path, name, XATTR_NOFOLLOW) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    /// Every attribute's name and size; empty when there are none or the item
    /// can't be read.
    static func names(at url: URL) -> [ExtendedAttribute] {
        return url.withUnsafeFileSystemRepresentation { path -> [ExtendedAttribute] in
            guard let path else { return [] }
            let length = listxattr(path, nil, 0, XATTR_NOFOLLOW)
            guard length > 0 else { return [] }
            var buffer = [CChar](repeating: 0, count: length)
            let read = listxattr(path, &buffer, length, XATTR_NOFOLLOW)
            guard read > 0 else { return [] }
            // The names are NUL-terminated, one after another.
            return buffer[..<read].split(separator: 0).map { bytes in
                let name = String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
                return ExtendedAttribute(name: name, size: max(size, 0))
            }
        }
    }
}
