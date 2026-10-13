import Foundation

extension FileSettings {
    /// Why Text Extensions can't add `typed`, or `nil` if it can.
    static func textExtensionProblem(_ typed: String, existing: [String])
        -> TextExtensionProblem?
    {
        let ext = normalizedExtension(typed)
        if ext.isEmpty { return .empty }
        if ext.contains("/") { return .slash }
        if ext.contains(".") { return .dot }
        if textExtensions(from: existing).contains(ext) { return .listed(ext) }
        if let kind = KnownExtensions.kind(of: ext) { return .known(ext, kind) }
        return nil
    }

    /// Whether a list is in Text Extensions' written form: each extension
    /// trimmed and lowercase, without a dot or slash, not empty, and listed
    /// once.
    static func isWrittenTextExtensions(_ list: [String]) -> Bool {
        return Set(list).count == list.count
            && list.allSatisfy { ext in
                ext == normalizedExtension(ext) && !ext.isEmpty && !ext.contains("/")
                    && !ext.contains(".")
            }
    }
}

/// Why Text Extensions refuses an extension, shown beneath its field.
enum TextExtensionProblem: Equatable, Sendable {
    case empty
    case slash

    /// An extension is the part after the last dot, so it can't hold one.
    case dot
    case listed(String)

    /// Files already gives files with it a kind.
    case known(String, KnownExtensions.Kind)

    var reason: String {
        switch self {
        case .empty: return String(localized: "An extension can't be empty.")
        case .slash: return String(localized: "An extension can't contain “/”.")
        case .dot: return String(localized: "An extension can't contain a dot.")
        case .listed(let ext): return String(localized: ".\(ext) is already in the list.")
        case .known(let ext, let kind):
            switch kind {
            case .scheme: return String(localized: "Files already treats .\(ext) as Scheme source.")
            case .image: return String(localized: "Files already treats .\(ext) as an image.")
            case .video: return String(localized: "Files already treats .\(ext) as a video.")
            case .text: return String(localized: "Files already treats .\(ext) as text.")
            }
        }
    }
}
