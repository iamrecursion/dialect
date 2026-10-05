import Foundation

/// One deleted item.
struct BinItem: Identifiable, Hashable, Sendable {
    let id: UUID

    /// The name it has in the bin and restores under, which changes when a
    /// newer namesake arrives.
    let name: String

    /// Where it was, which is where it goes back to.
    let original: FilePath
    let deleted: Date
    let isDirectory: Bool

    /// The item, inside the bin.
    let url: URL

    private static let day: TimeInterval = 24 * 60 * 60

    /// Whole days until the bin empties itself of this item, rounded up so the
    /// last day is 1.
    func daysLeft(now: Date, after days: Int?) -> Int? {
        guard let days else { return nil }
        let left = deleted.addingTimeInterval(Double(days) * Self.day).timeIntervalSince(now)
        return max(0, Int((left / Self.day).rounded(.up)))
    }

    /// Whether it's been in the bin `days` or more.
    func isExpired(now: Date, after days: Int?) -> Bool {
        guard let days else { return false }
        return now >= deleted.addingTimeInterval(Double(days) * Self.day)
    }
}

/// The bin's directory: one directory per item, holding the item and its
/// record.
///
/// The record is written before the item is moved in, so an item is never in
/// the bin without one.
struct Bin: Sendable {
    let url: URL

    /// What `record.json` holds.
    struct Record: Codable, Equatable, Sendable {
        var format = 1
        var name: String
        var original: [String]
        var deleted: Date
    }

    /// Newest deletion first. A record without its item, as during a delete, is
    /// left out.
    func items() -> [BinItem] {
        var items: [BinItem] = []
        var unrecorded: [(id: UUID, directory: URL, isDirectory: Bool)] = []
        for (id, directory) in directories() {
            guard let isDirectory = Self.isDirectory(at: directory) else { continue }
            if let record = record(in: directory) {
                items.append(BinItem(record, id: id, isDirectory: isDirectory, in: directory))
            } else {
                unrecorded.append((id, directory, isDirectory))
            }
        }
        for found in unrecorded {
            let record = recovered(found.directory, among: items)
            items.append(
                BinItem(record, id: found.id, isDirectory: found.isDirectory, in: found.directory))
        }
        return items.sorted { $0.deleted > $1.deleted }
    }

    /// Removes records left without their items by a crash, and writes records
    /// for items found without one.
    func tidy() {
        for (_, directory) in directories() {
            if Self.isDirectory(at: directory) == nil {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        let items = items()
        for item in items where record(in: item.directory) == nil {
            let others = items.filter { $0.id != item.id }
            try? write(recovered(item.directory, among: others), in: item.directory)
        }
    }

    /// Whether the bin's directory is empty: a cheap check, for the folder
    /// More's Trash.
    var isEmpty: Bool {
        let entries = try? FileManager.default.contentsOfDirectory(
            atPath: url.path(percentEncoded: false))
        return entries?.isEmpty ?? true
    }

    /// The item with this ID, if it's still in the bin.
    func item(_ id: UUID) -> BinItem? {
        let directory = directory(for: id)
        guard let record = record(in: directory), let isDirectory = Self.isDirectory(at: directory)
        else { return nil }
        return BinItem(record, id: id, isDirectory: isDirectory, in: directory)
    }

    // MARK: Layout

    func directory(for id: UUID) -> URL {
        return url.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    static func record(in directory: URL) -> URL {
        return directory.appending(path: "record.json", directoryHint: .notDirectory)
    }

    static func item(in directory: URL) -> URL {
        return directory.appending(path: "item", directoryHint: .notDirectory)
    }

    // MARK: Records

    func record(in directory: URL) -> Record? {
        guard let data = try? Data(contentsOf: Self.record(in: directory)) else { return nil }
        return try? Self.decoder.decode(Record.self, from: data)
    }

    func write(_ record: Record, in directory: URL) throws {
        try Self.encoder.encode(record).write(to: Self.record(in: directory), options: .atomic)
    }

    /// Dates to the millisecond, so deletions moments apart keep their order.
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return encoder
    }()

    /// Reads dates with or without fractional seconds.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = (try? dateStyle.parse(string))
                ?? (try? Date.ISO8601FormatStyle().parse(string))
            {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not an ISO 8601 date: \(string)")
        }
        return decoder
    }()

    // MARK: Reading

    /// Each item's directory, by its ID.
    private func directories() -> [(id: UUID, directory: URL)] {
        let entries =
            (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))
            ?? []
        return entries.compactMap { entry in
            UUID(uuidString: entry.lastPathComponent).map { ($0, entry) }
        }
    }

    /// A record for an item found without one: "Recovered Item", numbered clear
    /// of the others, restoring to the root, deleted when its directory last
    /// changed.
    private func recovered(_ directory: URL, among others: [BinItem]) -> Record {
        let name = NameNumbering.nextFree(
            for: String(localized: "Recovered Item"), isDirectory: false,
            taken: others.map(\.name))
        let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
        return Record(
            name: name, original: [name], deleted: values?.contentModificationDate ?? Date())
    }

    /// Whether the item in `directory` is a directory, not following a link;
    /// `nil` when there's no item.
    private static func isDirectory(at directory: URL) -> Bool? {
        let values = try? item(in: directory).resourceValues(forKeys: [.isDirectoryKey])
        return values.map { $0.isDirectory == true }
    }
}

extension BinItem {
    /// An original path that climbs out of the root, or isn't a valid path,
    /// restores to the root.
    fileprivate init(_ record: Bin.Record, id: UUID, isDirectory: Bool, in directory: URL) {
        let isSafe = record.original.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".." && !component.contains("/")
        }
        let original = isSafe ? record.original : [record.name]
        self.init(
            id: id, name: record.name, original: FilePath(components: original),
            deleted: record.deleted, isDirectory: isDirectory, url: Bin.item(in: directory))
    }
}

/// An item restored from the bin: as it was in the bin, and where it went.
struct Restored: Hashable, Sendable {
    let item: BinItem
    let path: FilePath

    /// Whether it went back where it was, under its name in the bin, comparing
    /// names as APFS does.
    var isWhereItWas: Bool {
        let expected = ((item.original.parent ?? .root).appending(item.name)).components
        return expected.count == path.components.count
            && zip(expected, path.components).allSatisfy(NameRules.sameName)
    }

    /// What its alert says when it came back dated; `nil` when it went back
    /// where it was.
    var note: String? {
        guard !isWhereItWas, let name = path.name else { return nil }
        if !NameRules.sameName(name, item.name) {
            return String(
                localized: "It came back as \(name), as something in Files now has its name.")
        }
        let folder = (path.parent ?? .root).display
        return String(
            localized: "It came back in \(folder), as something in Files now has its folder's name."
        )
    }
}

extension BinItem {
    /// The item's directory in the bin, holding the item and its record.
    var directory: URL { url.deletingLastPathComponent() }

    /// Its record, under `name`.
    func record(named name: String) -> Bin.Record {
        return Bin.Record(name: name, original: original.components, deleted: deleted)
    }
}
