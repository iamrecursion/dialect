import Foundation

/// Sizes in rows and Info.
enum SizeDisplay {
    /// "—" while a folder's total is still being worked out.
    static func string(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
