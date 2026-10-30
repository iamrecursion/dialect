import CryptoKit
import Foundation

/// What the phone asks of the watch's Files.
struct FilesRequest: Codable, Sendable {
    static let currentFormat = 1

    var format = FilesRequest.currentFormat
    var body: Body

    enum Body: Codable, Equatable, Sendable {
        /// A folder's items from `offset`. A `token` at offset 0 asks whether
        /// the listing has changed since; a later page's says which listing
        /// it's a part of.
        case list(FilePath, offset: Int, token: String?)

        /// Folders' and sessions' totals.
        case sizes([FilePath])
        case info(FilePath)
        case recents

        /// As `list`, for the bin.
        case bin(offset: Int, token: String?)
    }

    init(body: Body) {
        self.body = body
    }
}

/// The watch's answer to a `FilesRequest`.
enum FilesReply: Codable, Equatable, Sendable {
    case listing(ListingPage)
    case bin(BinPage)

    /// The listing is still the one `token` names.
    case unchanged

    /// The totals known by the time the reply went, and those still being
    /// worked out.
    case sizes([FilePath: Int64], pending: [FilePath])
    case info(ItemInfo)
    case recents(pinned: [FileItem], recent: [FileItem])
    case missing
    case failed(String)

    /// The request wasn't in the watch's format, given here.
    case otherFormat(Int)
}

/// Part of a folder's listing, whose items are in the order of their names.
struct ListingPage: Codable, Equatable, Sendable {
    let items: [ListedItem]
    let settings: FolderViewSettings

    /// Names the whole listing and its settings.
    let token: String
    let total: Int
    let offset: Int
}

/// Part of the bin, newest deletion first.
struct BinPage: Codable, Equatable, Sendable {
    let items: [ListedBinItem]
    let token: String
    let total: Int
    let offset: Int
}

/// An item in a listing: without its folder's path, and with short keys, so
/// many fit a page.
struct ListedItem: Codable, Hashable, Sendable {
    let name: String
    let kind: FileKind
    let size: Int64?
    let created: Date?
    let modified: Date?
    let isReadOnly: Bool

    private enum CodingKeys: String, CodingKey {
        case name = "n"
        case kind = "k"
        case size = "s"
        case created = "c"
        case modified = "m"
        case isReadOnly = "r"
    }

    init(
        name: String, kind: FileKind, size: Int64?, created: Date?, modified: Date?,
        isReadOnly: Bool
    ) {
        self.name = name
        self.kind = kind
        self.size = size
        self.created = created
        self.modified = modified
        self.isReadOnly = isReadOnly
    }

    init(_ item: FileItem) {
        self.init(
            name: item.name, kind: item.kind, size: item.size, created: item.created,
            modified: item.modified, isReadOnly: item.isReadOnly)
    }

    func item(in folder: FilePath) -> FileItem {
        return FileItem(
            path: folder.appending(name), kind: kind, isDirectory: kind.isDirectory, size: size,
            created: created, modified: modified, isReadOnly: isReadOnly)
    }
}

/// An item in the bin, in a listing of the Trash.
struct ListedBinItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let original: FilePath
    let deleted: Date
    let kind: FileKind
}

/// An item's Info.
struct ItemInfo: Codable, Equatable, Sendable {
    let item: FileItem

    /// A file's size, or a folder's or session's total if it's known yet.
    let total: Int64?

    /// A folder's or session's count of entries.
    let count: Int?
    let extended: ExtendedInfo?
}

enum FilesCoding {
    /// Sorted keys, so the same value always makes the same bytes.
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        return try JSONDecoder().decode(type, from: data)
    }
}

/// Keeping requests and replies within a message.
enum FilesPaging {
    /// The most `sendMessageData` takes, each way.
    static let messageLimit = 64 * 1024

    /// What a page's items may take, leaving room for what's around them.
    static let budget = 60 * 1024

    /// The most paths a `sizes` request asks for.
    static let sizesLimit = 32

    /// The items from `offset` that fit `budget`, given each item's encoded
    /// length: at least one, so a listing always moves on. An offset outside
    /// the listing gives none.
    static func page(of lengths: [Int], from offset: Int, budget: Int = budget) -> Range<Int> {
        guard lengths.indices.contains(offset) else { return lengths.count..<lengths.count }
        var used = 0
        var end = offset
        while end < lengths.count {
            // With the comma between items.
            used += lengths[end] + 1
            if used > budget, end > offset { break }
            end += 1
        }
        return offset..<end
    }

    /// `paths` as `sizes` requests.
    static func batches(of paths: [FilePath]) -> [[FilePath]] {
        var batches: [[FilePath]] = []
        var used = 0
        for path in paths {
            let length = ((try? FilesCoding.encode(path).count) ?? budget) + 1
            if let last = batches.last, last.count < sizesLimit, used + length <= budget {
                batches[batches.count - 1].append(path)
                used += length
            } else {
                batches.append([path])
                used = length
            }
        }
        return batches
    }

    /// Names a listing: every item's encoded form, and then what else its reply
    /// says about it.
    static func token(of encodedItems: [Data], and extra: Data = Data()) -> String {
        var hash = SHA256()
        for item in encodedItems {
            hash.update(data: item)
            hash.update(data: Data([0]))
        }
        hash.update(data: extra)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// A request and its answer as user info, for when the watch isn't reachable.
struct FilesUserInfo: Sendable {
    let id: String
    let data: Data

    /// When the phone asked; `nil` for an answer.
    let sent: Date?

    private enum Key {
        static let request = "filesRequest"
        static let answer = "filesAnswer"
        static let id = "filesID"
        static let sent = "filesSent"
    }

    /// A request in user info.
    init?(request list: [String: Any]) {
        guard let data = list[Key.request] as? Data, let id = list[Key.id] as? String,
            let sent = list[Key.sent] as? Date
        else { return nil }
        self.init(id: id, data: data, sent: sent)
    }

    /// An answer in user info.
    init?(answer list: [String: Any]) {
        guard let data = list[Key.answer] as? Data, let id = list[Key.id] as? String else {
            return nil
        }
        self.init(id: id, data: data, sent: nil)
    }

    init(id: String, data: Data, sent: Date?) {
        self.id = id
        self.data = data
        self.sent = sent
    }

    var propertyList: [String: Any] {
        guard let sent else { return [Key.answer: data, Key.id: id] }
        return [Key.request: data, Key.id: id, Key.sent: sent]
    }
}
