import Foundation

/// What an item is, which decides its icon, its group and its type name.
enum FileKind: Sendable, CaseIterable {
    /// A directory, unless it's named like a session.
    case folder

    /// A directory named `name.dial`, shown as one item.
    case session

    /// Scheme source: a file with one of `schemeExtensions`.
    case scheme

    /// A text document: a file with one of `textExtensions`, or one of the
    /// user's Settings › Files › Text Extensions.
    case text

    /// An image: a file with one of `imageExtensions`.
    case image

    /// A video: a file with one of `videoExtensions`.
    case video

    /// A file of no known kind that reads as UTF-8 text.
    case otherText

    /// A file of no known kind that doesn't read as UTF-8, and anything that
    /// isn't a regular file or a directory, such as a named pipe, or a broken
    /// link.
    case binary

    /// The extensions of Scheme source, lowercase and without the dot, as all
    /// these sets are: `.scm` for programs and `.sld` for R7RS libraries.
    static let schemeExtensions: Set = ["scm", "sld"]

    /// The extensions of text documents, without the user's.
    static let textExtensions: Set = ["md", "txt", "toml", "yaml", "json", "xml", "csv"]

    /// The extensions of images.
    static let imageExtensions: Set = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "jxl",
    ]

    /// The extensions of videos.
    static let videoExtensions: Set = ["mp4", "mov", "m4v"]

    /// How many bytes the text-like check reads from the start of a file.
    static let sniffLength = 4096

    /// The kind an item's name and type decide, or `nil` for a file whose
    /// extension isn't known, which `sniff` then decides.
    ///
    /// `textExtensions` are the user's, lowercase and without the dot.
    static func classify(name: String, isDirectory: Bool, textExtensions: Set<String>)
        -> FileKind?
    {
        let ext = FileItem.splitName(name).ext.lowercased()
        if isDirectory {
            return ext == "dial" ? .session : .folder
        }
        if schemeExtensions.contains(ext) { return .scheme }
        if self.textExtensions.contains(ext) || textExtensions.contains(ext) { return .text }
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        return nil
    }

    /// `.otherText` when the file's first 4 KB are valid UTF-8 with no NUL
    /// bytes (or the file is empty), otherwise `.binary`. A file that can't be
    /// read is binary.
    static func sniff(_ url: URL) -> FileKind {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .binary }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: sniffLength) else { return .otherText }
        return isTextLike(data, cut: data.count == sniffLength) ? .otherText : .binary
    }

    /// The text-like check on bytes already read. `cut` says the bytes stop at
    /// the read limit before the end of the file, so a character split by the
    /// limit is forgiven.
    static func isTextLike(_ data: Data, cut: Bool) -> Bool {
        if data.contains(0) { return false }
        if String(validating: data, as: UTF8.self) != nil { return true }
        guard cut else { return false }
        return String(validating: data[..<completeEnd(of: data)], as: UTF8.self) != nil
    }

    /// Where the bytes end without a final, partial character: a lead byte
    /// followed by fewer continuation bytes than it needs. Anything else is
    /// left to validation.
    private static func completeEnd(of data: Data) -> Data.Index {
        var end = data.endIndex
        var continuations = 0
        while continuations < 3, end > data.startIndex, data[end - 1] & 0xC0 == 0x80 {
            end -= 1
            continuations += 1
        }
        guard end > data.startIndex else { return data.endIndex }
        let lead = data[end - 1]
        let length: Int
        switch lead {
        case 0xF0...0xF7: length = 4
        case 0xE0...0xEF: length = 3
        case 0xC0...0xDF: length = 2
        default: return data.endIndex
        }
        return continuations + 1 < length ? end - 1 : data.endIndex
    }

    var group: KindGroup {
        switch self {
        case .folder: return .folders
        case .session: return .sessions
        case .scheme: return .scheme
        case .text: return .text
        case .image: return .images
        case .video: return .videos
        case .otherText, .binary: return .other
        }
    }

    /// The kind spelled out, as Info's Type shows it.
    var typeName: LocalizedStringResource {
        switch self {
        case .folder: return "Folder"
        case .session: return "Session"
        case .scheme: return "Scheme Source"
        case .text: return "Text Document"
        case .image: return "Image"
        case .video: return "Video"
        case .otherText: return "Document"
        case .binary: return "Binary File"
        }
    }
}

/// The groups of Group by Kind.
enum KindGroup: Sendable, CaseIterable {
    case folders, sessions, scheme, text, images, videos, other

    var title: LocalizedStringResource {
        switch self {
        case .folders: return "Folders"
        case .sessions: return "Sessions"
        case .scheme: return "Scheme"
        case .text: return "Text"
        case .images: return "Images"
        case .videos: return "Videos"
        case .other: return "Other"
        }
    }
}
