import Foundation

/// The extensions by which Files knows a file's kind. Each set is lowercase,
/// without dots.
enum KnownExtensions {
    enum Kind: Sendable {
        case scheme
        case text
        case image
        case video
    }

    /// Scheme source: `.scm` for programs and `.sld` for R7RS libraries.
    static let scheme: Set = ["scm", "sld"]

    /// Text documents, without the user's Text Extensions.
    static let text: Set = ["md", "txt", "toml", "yaml", "json", "xml", "csv"]

    static let image: Set = ["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "jxl"]

    static let video: Set = ["mp4", "mov", "m4v"]

    /// The kind of a lowercase extension, if Files knows it.
    static func kind(of ext: String) -> Kind? {
        if scheme.contains(ext) { return .scheme }
        if text.contains(ext) { return .text }
        if image.contains(ext) { return .image }
        if video.contains(ext) { return .video }
        return nil
    }
}
