import CryptoKit
import Foundation

/// One operation in the undo history.
///
/// Undoing a step reverses its changes, last first, and returns the step that
/// redoes it. An item that leaves the bin goes back under its ID, so steps
/// beneath it can still find it.
struct Step: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case rename, move, paste, newFolder, newSession, newFile, delete, restore
    }

    /// Where an item is.
    enum Place: Codable, Equatable, Sendable {
        case files(FilePath)

        /// In the bin under `id`, with the record it had there.
        case bin(id: UUID, record: Bin.Record)
    }

    /// One item's part in a step.
    struct Change: Codable, Equatable, Sendable {
        /// `nil` for an item the step made, which undoing sends to the bin.
        let from: Place?
        let to: Place

        /// Marks the item a Replace displaced, which labels don't count.
        var replaced = false

        /// A hash of the item as the step left it, for one that reversing sends
        /// to the bin. Undo asks first if it's changed since.
        var signature: String?

        /// Whether reversing it sends the item from Files to the bin.
        var sendsToBin: Bool {
            guard case .files = to else { return false }
            if case .files = from { return false }
            return true
        }

        /// The item's path in Files: where it is, or where it was before the
        /// bin.
        var path: FilePath? {
            switch (to, from) {
            case (.files(let path), _), (.bin, .files(let path)?): return path
            default: return nil
            }
        }
    }

    let kind: Kind
    var changes: [Change]

    /// Folders the step made for its items, outermost first. Reversing it
    /// removes those left empty.
    var madeFolders: [FilePath]?

    /// Folders the reversal that gave this step removed, outermost first.
    /// Reversing it makes them again first.
    var removedFolders: [FilePath]?
}

/// The undo and redo stacks, newest last.
///
/// Reading never writes, so screens can read it off the actor; only
/// `FileOperations` changes it.
struct History: Sendable {
    /// The file it's kept in, written whole each time.
    let url: URL

    struct Stacks: Codable, Equatable, Sendable {
        var format = 1
        var undo: [Step] = []
        var redo: [Step] = []

        /// Adds a step, clearing Redo and keeping the newest `limit` steps.
        mutating func record(_ step: Step, limit: Int) {
            undo.append(step)
            redo = []
            trim(to: limit)
        }

        /// How many steps keeping `limit` would drop.
        func excess(over limit: Int) -> Int {
            return max(0, undo.count + redo.count - limit)
        }

        /// Keeps `limit` steps, dropping the oldest: Undo's first, then those
        /// Redo would reach last.
        mutating func trim(to limit: Int) {
            let excess = excess(over: limit)
            let fromUndo = min(excess, undo.count)
            undo.removeFirst(fromUndo)
            redo.removeFirst(excess - fromUndo)
        }
    }

    /// Both stacks; empty when the file can't be read.
    func read() -> Stacks {
        guard let data = try? Data(contentsOf: url),
            let stacks = try? JSONDecoder().decode(Stacks.self, from: data)
        else { return Stacks() }
        return stacks
    }

    func write(_ stacks: Stacks) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(stacks).write(to: url, options: .atomic)
    }
}

extension BinItem {
    /// Where it is, for a step.
    var place: Step.Place { .bin(id: id, record: record(named: name)) }
}

extension NewItemKind {
    var newStep: Step.Kind {
        switch self {
        case .folder: return .newFolder
        case .session: return .newSession
        case .file: return .newFile
        }
    }
}

extension FilePath: Codable {
    /// Refuses a path that could reach outside the root, so a damaged history
    /// reads as empty.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let components = try container.decode([String].self)
        guard
            components.allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/")
            })
        else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not a path in Files: \(components)")
        }
        self.init(components: components)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(components)
    }
}

extension FileOperations {
    /// The history in `stores`.
    nonisolated var history: History { History(url: FilesStores.history(in: stores)) }

    /// Adds `step` to the history. A failure to write loses only the step.
    func record(_ step: Step) {
        guard !step.changes.isEmpty else { return }
        var stacks = history.read()
        stacks.record(signed(step), limit: historyLength())
        try? history.write(stacks)
    }

    /// `step` with a signature for each item that reversing it sends to the
    /// bin.
    func signed(_ step: Step) -> Step {
        var step = step
        for index in step.changes.indices where step.changes[index].sendsToBin {
            if case .files(let path) = step.changes[index].to {
                step.changes[index].signature = signature(of: path)
            }
        }
        return step
    }

    /// A hash of the item at `path`: every name inside it, with each file's
    /// size and modification time. Folders' dates are left out, as undoing a
    /// step inside a folder changes its date. `nil` when it can't be read, or
    /// holds more than `limit` items, which take too long to hash on a watch.
    nonisolated func signature(of path: FilePath, limit: Int = 2_000) -> String? {
        let url = path.url(in: root)
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
        ]
        func line(_ item: URL, _ name: String) -> String? {
            guard let values = try? item.resourceValues(forKeys: keys) else { return nil }
            if values.isDirectory == true && values.isSymbolicLink != true { return name + "/" }
            let modified = values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            return "\(name)|\(values.fileSize ?? 0)|\(modified)"
        }
        guard let top = line(url, "") else { return nil }
        var lines = [top]
        if top == "/" {
            // Relative paths, as the URLs an enumerator gives can resolve `/var` to `/private/var`.
            guard
                let inside = FileManager.default.enumerator(
                    atPath: url.path(percentEncoded: false))
            else { return nil }
            for case let relative as String in inside {
                if lines.count > limit { return nil }
                lines.append(line(url.appending(path: relative), relative) ?? "?")
            }
        }
        let digest = SHA256.hash(data: Data(lines.sorted().joined(separator: "\n").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Drops the oldest steps beyond `limit`, for a shorter Undo History.
    func trimHistory(to limit: Int) throws {
        var stacks = history.read()
        guard stacks.excess(over: limit) > 0 else { return }
        stacks.trim(to: limit)
        try history.write(stacks)
    }
}
