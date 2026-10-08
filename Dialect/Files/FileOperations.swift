import Foundation

/// Why an operation failed.
enum FileOperationError: LocalizedError, Equatable, Sendable {
    /// The specified name can't be used in the folder.
    case name(NameProblem)

    /// The item, or the folder it was going into, has disappeared.
    case gone(String)

    /// Move was asked to put a folder into itself, or into a folder inside it.
    case intoItself(String)
    case intoOwnFolder(String)

    var errorDescription: String? {
        switch self {
        case .name(let problem): return problem.reason
        case .gone(let name): return String(localized: "\(name) is no longer there.")
        case .intoItself(let name): return String(localized: "\(name) can't be moved into itself.")
        case .intoOwnFolder(let name):
            return String(localized: "\(name) can't be moved into a folder inside it.")
        }
    }
}

/// A bulk operation that stopped at an item it couldn't process.
struct PartialFailure<Done: Sendable>: LocalizedError {
    let done: [Done]
    let underlying: any Error

    var errorDescription: String? { underlying.localizedDescription }

    static func of(_ error: any Error, after done: [Done]) -> any Error {
        return done.isEmpty ? error : PartialFailure(done: done, underlying: error)
    }
}

/// Every change Files makes to the user's files, one at a time to avoid races.
actor FileOperations {
    let root: URL
    let stores: URL
    let sizes: FolderSizes

    /// How many steps the undo history keeps.
    let historyLength: @Sendable () -> Int

    init(
        root: URL, stores: URL, sizes: FolderSizes = .shared,
        historyLength: @escaping @Sendable () -> Int = { FileSettings.undoHistory() }
    ) {
        self.root = root
        self.stores = stores
        self.sizes = sizes
        self.historyLength = historyLength
    }

    /// Removes what an interrupted operation left in staging.
    func clearStaging() {
        try? FileManager.default.removeItem(at: FilesStores.staging(in: stores))
    }

    // MARK: Making

    func createFolder(named name: String, in folder: FilePath) async throws -> FilePath {
        return try await create(name, kind: .folder, in: folder) { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
    }

    /// A session: its directory, a manifest, and an empty source.
    func createSession(named name: String, in folder: FilePath) async throws -> FilePath {
        return try await create(name, kind: .session, in: folder) { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try Data("{\"format\": 1}\n".utf8).write(to: url.appending(path: "manifest.json"))
            try Data().write(to: url.appending(path: "main.scm"))
        }
    }

    /// An empty file.
    func createFile(named name: String, in folder: FilePath) async throws -> FilePath {
        return try await create(name, kind: .file, in: folder) { url in
            try Data().write(to: url)
        }
    }

    /// Makes the item in staging with `make`, then renames it into place.
    func create(
        _ name: String, kind: NewItemKind, in folder: FilePath,
        make: (URL) throws -> Void
    ) async throws -> FilePath {
        try check(name, kind: kind, in: folder)
        pruneHeld()
        let staging = FilesStores.staging(in: stores)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appending(path: UUID().uuidString, directoryHint: .notDirectory)
        let made = folder.appending(name)
        do {
            try make(staged)
            try place(
                staged, to: made.url(in: root), named: name, goneName: Self.displayName(of: folder))
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
        // Before any await, so the history keeps the order things happened in.
        record(Step(kind: kind.newStep, changes: [Step.Change(from: nil, to: .files(made))]))
        await sizes.forget(containing: made.url(in: root))
        return made
    }

    // MARK: Renaming

    /// Renames the item, keeping everything on it, such as a folder's view
    /// settings. Returns its new location.
    func rename(_ path: FilePath, to name: String) async throws -> FilePath {
        guard let old = path.name, let folder = path.parent else {
            preconditionFailure("Files' root can't be renamed")
        }
        let url = path.url(in: root)
        guard let kind = Self.kind(at: url) else { throw FileOperationError.gone(old) }
        // Equal in either Unicode form. Foundation writes every name decomposed, so there's nothing
        // to rename.
        if name == old { return path }
        try check(name, kind: kind, in: folder, current: old)
        pruneHeld()
        let renamed = folder.appending(name)
        try place(url, to: renamed.url(in: root), named: name, goneName: old)
        updateClipboard { $0.following(path, to: renamed) }
        updateRecents { $0.following(path, to: renamed) }
        record(
            Step(kind: .rename, changes: [Step.Change(from: .files(path), to: .files(renamed))]))
        await sizes.forget(containing: url)
        await sizes.forget(containing: renamed.url(in: root))
        return renamed
    }

    // MARK: The bin

    /// The bin in `stores`.
    nonisolated var bin: Bin { Bin(url: FilesStores.bin(in: stores)) }

    /// Moves each item into the bin, in order, stopping at the first that can't
    /// be.
    func delete(_ paths: [FilePath], now: Date = Date()) async throws -> [BinItem] {
        var deleted: [BinItem] = []
        for path in paths {
            do {
                deleted.append(try moveIntoBin(path, now: now))
            } catch {
                let done = paths.prefix(deleted.count)
                updateClipboard { held in done.reduce(held) { $0.dropping(within: $1) } }
                updateRecents { held in done.reduce(held) { $0.dropping(within: $1) } }
                record(Self.deleteStep(done, deleted))
                await forget(done.map { $0.url(in: root) })
                throw PartialFailure.of(error, after: deleted)
            }
        }
        updateClipboard { held in paths.reduce(held) { $0.dropping(within: $1) } }
        updateRecents { held in paths.reduce(held) { $0.dropping(within: $1) } }
        record(Self.deleteStep(paths, deleted))
        await forget(paths.map { $0.url(in: root) })
        return deleted
    }

    private static func deleteStep(_ paths: some Sequence<FilePath>, _ deleted: [BinItem]) -> Step {
        return Step(
            kind: .delete,
            changes: zip(paths, deleted).map { Step.Change(from: .files($0), to: $1.place) })
    }

    func moveIntoBin(_ path: FilePath, now: Date, id: UUID = UUID()) throws -> BinItem {
        guard let name = path.name else { preconditionFailure("Files' root can't be deleted") }
        return try moveIntoBin(
            path, as: Bin.Record(name: name, original: path.components, deleted: now), id: id)
    }

    /// The record first, then the item, so the item is never in the bin without
    /// it. If there is a clash, the older deletion is renamed to the next free
    /// number, so a new deletion always takes the clashing name.
    func moveIntoBin(_ path: FilePath, as record: Bin.Record, id: UUID = UUID()) throws
        -> BinItem
    {
        guard let name = path.name else { preconditionFailure("Files' root can't be deleted") }
        let url = path.url(in: root)
        guard let kind = Self.kind(at: url) else { throw FileOperationError.gone(name) }
        let bin = self.bin
        try FileManager.default.createDirectory(at: bin.url, withIntermediateDirectories: true)

        // First, so a failure never removes a directory it didn't make.
        let directory = bin.directory(for: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)

        var record = record
        let items = bin.items()
        let taken = items.map(\.name)
        var holder = items.first { NameRules.sameName($0.name, record.name) }
        if let newer = holder, newer.deleted > record.deleted {
            record.name = NameNumbering.nextFree(
                for: record.name, isDirectory: kind != .file, taken: taken)
            holder = nil
        }
        do {
            if let holder {
                let renamed = NameNumbering.nextFree(
                    for: holder.name, isDirectory: holder.isDirectory, taken: taken)
                try bin.write(holder.record(named: renamed), in: holder.directory)
            }
            try bin.write(record, in: directory)
            try place(url, to: Bin.item(in: directory), named: name, goneName: name)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            if let holder {
                try? bin.write(holder.record(named: holder.name), in: holder.directory)
            }
            throw error
        }
        guard let item = bin.item(id) else { throw FileOperationError.gone(name) }
        return item
    }

    /// Puts the item back where it was, recreating missing folders. A taken
    /// name gets the deletion date added, as does a folder on its path where a
    /// file now stands. Returns where it went.
    func restore(_ item: BinItem, timeZone: TimeZone = .current) async throws -> Restored {
        bin.tidy()
        pruneHeld()
        let restored = try moveOutOfBin(item, timeZone: timeZone)
        record(Self.restoreStep([restored]))
        await forget([restored.path.url(in: root)])
        return restored
    }

    /// Restores everything, as one step.
    func restoreAll(timeZone: TimeZone = .current) async throws -> [Restored] {
        return try await restore(bin.items(), timeZone: timeZone)
    }

    /// Restores the items as one step, newest deletion first, which undoes the
    /// deletes in reverse: after `a/b/f` and then `a` were deleted, `a` comes
    /// back first and `f` goes back into it. Stops at the first item that can't
    /// be restored.
    func restore(_ items: [BinItem], timeZone: TimeZone = .current) async throws -> [Restored] {
        var restored: [Restored] = []
        let bin = self.bin
        bin.tidy()
        pruneHeld()
        let newestFirst = items.sorted { $0.deleted > $1.deleted }
        for item in newestFirst {
            do {
                restored.append(try moveOutOfBin(item, timeZone: timeZone))
            } catch {
                record(Self.restoreStep(restored))
                await forget(restored.map { $0.path.url(in: root) })
                throw PartialFailure.of(error, after: restored)
            }
        }
        record(Self.restoreStep(restored))
        await forget(restored.map { $0.path.url(in: root) })
        return restored
    }

    private static func restoreStep(_ restored: [Restored]) -> Step {
        let made = restored.flatMap(\.made)
        return Step(
            kind: .restore,
            changes: restored.map { Step.Change(from: $0.item.place, to: .files($0.path)) },
            madeFolders: made.isEmpty ? nil : made)
    }

    /// The item as it is in the bin now.
    func moveOutOfBin(_ listed: BinItem, timeZone: TimeZone) throws -> Restored {
        guard let item = bin.item(listed.id) else { throw FileOperationError.gone(listed.name) }
        let (folder, made) = try recreate(
            item.original.parent ?? .root, deleted: item.deleted, timeZone: timeZone)
        let restored: FilePath
        do {
            let taken = try contents(of: folder)
            var name = item.name
            if taken.contains(where: { NameRules.sameName($0, name) }) {
                let dated = NameNumbering.dated(
                    name, isDirectory: item.isDirectory, deleted: item.deleted, timeZone: timeZone)
                name = NameNumbering.nextFree(
                    for: dated, isDirectory: item.isDirectory, taken: taken)
            }
            restored = folder.appending(name)
            try place(item.url, to: restored.url(in: root), named: name, goneName: item.name)
        } catch {
            _ = removeEmpty(made)
            throw error
        }
        try? FileManager.default.removeItem(at: item.directory)
        return Restored(item: item, path: restored, made: made)
    }

    /// The folder at `path`, recreated if missing, and the folders made,
    /// outermost first.
    private func recreate(_ path: FilePath, deleted: Date, timeZone: TimeZone) throws -> (
        FilePath, made: [FilePath]
    ) {
        var folder = FilePath.root
        var made: [FilePath] = []
        for component in path.components {
            let dated = NameNumbering.dated(
                component, isDirectory: true, deleted: deleted, timeZone: timeZone)
            var blocked: [String] = []
            var candidate = component
            while true {
                if let entered = try enter(candidate, in: folder) {
                    folder = entered.path
                    if entered.made { made.append(entered.path) }
                    break
                }
                blocked.append(candidate)
                candidate = NameNumbering.nextFree(for: dated, isDirectory: true, taken: blocked)
            }
        }
        return (folder, made)
    }

    /// The folder `name` in `folder`, made if nothing has the name; `nil` when
    /// something that isn't a folder has it.
    private func enter(_ name: String, in folder: FilePath) throws -> (path: FilePath, made: Bool)?
    {
        if let existing = try contents(of: folder).first(where: { NameRules.sameName($0, name) }) {
            let path = folder.appending(existing)
            let kind = Self.kind(at: path.url(in: root))
            return kind == .folder || kind == .session ? (path, false) : nil
        }
        let path = folder.appending(name)
        try FileManager.default.createDirectory(
            at: path.url(in: root), withIntermediateDirectories: false)
        return (path, true)
    }

    /// Removes the items from the bin for good. One already gone is skipped.
    func deletePermanently(_ items: [BinItem]) throws {
        var removed: [BinItem] = []
        for item in items {
            do {
                try discard(item.directory)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                // Gone already, which is what was asked.
            } catch {
                throw PartialFailure.of(error, after: removed)
            }
            removed.append(item)
        }
    }

    /// Empties the bin.
    func deleteAll() throws {
        do {
            try discard(bin.url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Never used, so already empty.
        }
    }

    /// Removes what's been in the bin `days` or more, or nothing when `days` is
    /// `nil`, after tidying what a crash left.
    @discardableResult
    func removeExpired(now: Date = Date(), after days: Int?) -> Int {
        let bin = self.bin
        bin.tidy()
        var removed = 0
        for item in bin.items() where item.isExpired(now: now, after: days) {
            if (try? discard(item.directory)) != nil { removed += 1 }
        }
        return removed
    }

    /// Removes `url` by way of staging: it leaves the bin in one step, so an
    /// interrupted removal never leaves half an item there. Clearing staging at
    /// launch finishes the removal.
    private func discard(_ url: URL) throws {
        let staging = FilesStores.staging(in: stores)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let doomed = staging.appending(path: UUID().uuidString, directoryHint: .notDirectory)
        try AtomicRename.rename(url, to: doomed)
        try? FileManager.default.removeItem(at: doomed)
    }

    // MARK: Folder sizes

    /// Drops the cached totals above and inside each changed item.
    func forget(_ urls: [URL]) async {
        for url in urls { await sizes.forget(containing: url) }
    }

    // MARK: Checks

    /// Throws if `name` can't be used in `folder` as it is now.
    private func check(
        _ name: String, kind: NewItemKind, in folder: FilePath, current: String? = nil
    ) throws {
        if let problem = NameRules.problem(
            typed: name, full: name, kind: kind, taken: try contents(of: folder),
            current: current)
        {
            throw FileOperationError.name(problem)
        }
    }

    /// Every name in `folder`, hidden ones included.
    func contents(of folder: FilePath) throws -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(
                atPath: folder.url(in: root).path(percentEncoded: false))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw FileOperationError.gone(Self.displayName(of: folder))
        }
    }

    /// Renames `url` to `destination`, reporting a name taken since the check
    /// as taken.
    func place(_ url: URL, to destination: URL, named name: String, goneName: String)
        throws
    {
        do {
            try AtomicRename.rename(url, to: destination)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            throw FileOperationError.name(.taken(name))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            throw FileOperationError.gone(goneName)
        }
    }

    /// The item's shape as listed, a link as what it leads to; `nil` if it's
    /// gone. A broken link is a file.
    static func kind(at url: URL) -> NewItemKind? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard var values = try? url.resourceValues(forKeys: keys) else { return nil }
        if values.isSymbolicLink == true {
            guard let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: keys)
            else { return .file }
            values = target
        }
        guard values.isDirectory == true else { return .file }
        return FileItem.splitName(url.lastPathComponent).ext.lowercased() == "dial"
            ? .session : .folder
    }

    static func displayName(of folder: FilePath) -> String {
        return folder.name ?? String(localized: "Files")
    }
}
