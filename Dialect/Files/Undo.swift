import Foundation

/// Why Undo or Redo can't reverse the last step, which is then dropped.
struct UndoProblem: LocalizedError, Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        /// The item isn't where the step left it.
        case gone(String, in: FilePath)

        /// The bin no longer holds the item: it expired, or was deleted
        /// permanently.
        case notInBin(String)

        /// Something else has the item's name where it's going back to.
        case taken(String, in: FilePath)

        /// The folder it's going back to isn't there, or isn't a folder.
        case folderGone(FilePath)
        case notAFolder(FilePath)

        /// The step can't be read as one Files would record.
        case unreadable
    }

    let undoing: Bool
    let reason: Reason

    var errorDescription: String? {
        switch (undoing, reason) {
        case (true, .gone(let name, let folder)):
            return String(
                localized: "This can't be undone, as \(name) is no longer in \(folder.messageName)."
            )
        case (false, .gone(let name, let folder)):
            return String(
                localized: "This can't be redone, as \(name) is no longer in \(folder.messageName)."
            )
        case (true, .notInBin(let name)):
            return String(localized: "This can't be undone, as \(name) is no longer in the Trash.")
        case (false, .notInBin(let name)):
            return String(localized: "This can't be redone, as \(name) is no longer in the Trash.")
        case (true, .taken(let name, let folder)):
            return String(
                localized:
                    "This can't be undone, as something in \(folder.messageName) now has the name \(name)."
            )
        case (false, .taken(let name, let folder)):
            return String(
                localized:
                    "This can't be redone, as something in \(folder.messageName) now has the name \(name)."
            )
        case (true, .folderGone(let folder)):
            return String(
                localized: "This can't be undone, as \(folder.display) is no longer there.")
        case (false, .folderGone(let folder)):
            return String(
                localized: "This can't be redone, as \(folder.display) is no longer there.")
        case (true, .notAFolder(let folder)):
            return String(
                localized: "This can't be undone, as \(folder.display) is no longer a folder.")
        case (false, .notAFolder(let folder)):
            return String(
                localized: "This can't be redone, as \(folder.display) is no longer a folder.")
        case (true, .unreadable): return String(localized: "This can't be undone.")
        case (false, .unreadable): return String(localized: "This can't be redone.")
        }
    }
}

/// An Undo or Redo that would send to the bin items changed since the step. It
/// asks first, and the step stays.
struct UndoChanged: Error, Equatable, Sendable {
    let undoing: Bool

    /// The changed items' names.
    let names: [String]

    /// The question the confirmation asks.
    var question: String {
        return names.count == 1
            ? String(localized: "\(names[0]) has changed since. Move it to the Trash anyway?")
            : String(
                localized: "\(names.count) items have changed since. Move them to the Trash anyway?"
            )
    }
}

/// An Undo or Redo that stopped part way. The step is dropped.
struct UndoStopped: LocalizedError {
    let done: [Step.Change]

    /// The paths it took items from and the folders it removed, for screens
    /// showing them to leave.
    let vacated: [FilePath]
    let underlying: any Error

    var errorDescription: String? { underlying.localizedDescription }
}

extension FilePath {
    /// A folder as messages name it: `/notes`, or Files at the root.
    var messageName: String { self == .root ? String(localized: "Files") : display }
}

extension FileOperations {
    /// Reverses the last step, which Redo can then reapply. Returns the paths
    /// it took items from, for screens showing them to leave. Unless
    /// `confirmed` an item changed since the step throws `UndoChanged`.
    func undo(confirmed: Bool = false) async throws -> [FilePath] {
        return try await reverse(undoing: true, confirmed: confirmed)
    }

    /// Reapplies the last step undone.
    func redo(confirmed: Bool = false) async throws -> [FilePath] {
        return try await reverse(undoing: false, confirmed: confirmed)
    }

    /// Takes the last step from one stack, checks it all, reverses it, and puts
    /// the reversal on the other. A step that fails its checks, or stops part
    /// way, is dropped; what was done stays done. Folders the step made are
    /// removed after its items leave, and made again before they return.
    private func reverse(undoing: Bool, confirmed: Bool) async throws -> [FilePath] {
        // A record left by a crash would hold an ID that an item is going back under.
        bin.tidy()
        var stacks = history.read()
        guard let step = undoing ? stacks.undo.popLast() : stacks.redo.popLast() else {
            return []
        }
        let changes = Array(step.changes.reversed())
        let making = step.removedFolders ?? []
        if let reason = problem(reversing: changes, making: making) {
            try? history.write(stacks)
            throw UndoProblem(undoing: undoing, reason: reason)
        }
        var changed: [FilePath] = []
        for change in changes where change.sendsToBin {
            guard let signature = change.signature, case .files(let path) = change.to,
                !changed.contains(path), self.signature(of: path) != signature
            else { continue }
            changed.append(path)
        }
        if !confirmed && !changed.isEmpty {
            throw UndoChanged(undoing: undoing, names: changed.compactMap(\.name))
        }
        pruneClipboard()
        // An undone Restore goes back with its old deletion date. Anything else, or changed since,
        // goes back as a new deletion, so it can't expire at once.
        let restoring = undoing && step.kind == .restore
        var made: [FilePath] = []
        var done: [Step.Change] = []
        do {
            for folder in making {
                if try makeFolder(folder) { made.append(folder) }
            }
            for change in changes {
                let isChanged = change.path.map(changed.contains) ?? false
                done.append(
                    try reverse(change, undoing: undoing, keepsRecord: restoring && !isChanged))
            }
        } catch {
            try? history.write(stacks)
            // The step is dropped, so no later trip would remove what's left empty.
            let emptied = removeEmpty(made + (step.madeFolders ?? []))
            await finish(done, folders: made + emptied)
            if done.isEmpty { throw error }
            throw UndoStopped(done: done, vacated: done.vacated + emptied, underlying: error)
        }
        let removed = removeEmpty(step.madeFolders ?? [])
        let reversal = signed(
            Step(
                kind: step.kind, changes: done, madeFolders: made.isEmpty ? nil : made,
                removedFolders: removed.isEmpty ? nil : removed))
        if undoing {
            stacks.redo.append(reversal)
        } else {
            stacks.undo.append(reversal)
        }
        try? history.write(stacks)
        await finish(done, folders: made + removed)
        return done.vacated + removed
    }

    /// Makes the folder unless one is already there; returns whether it made
    /// it.
    private func makeFolder(_ folder: FilePath) throws -> Bool {
        let url = folder.url(in: root)
        if let kind = Self.kind(at: url), kind != .file { return false }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return true
    }

    /// Removes each folder that's empty, innermost first. Returns those
    /// removed, outermost first.
    func removeEmpty(_ folders: [FilePath]) -> [FilePath] {
        var removed: [FilePath] = []
        for folder in folders.reversed() {
            // `rmdir` removes only an empty folder.
            let isRemoved = folder.url(in: root).withUnsafeFileSystemRepresentation {
                path -> Bool in
                guard let path else { return false }
                return rmdir(path) == 0
            }
            if isRemoved { removed.insert(folder, at: 0) }
        }
        return removed
    }

    /// Takes one item from where `change` left it back to where it was, and
    /// returns the change that did it. An item going back into the bin keeps
    /// its ID, and its record too when `keepsRecord`.
    private func reverse(_ change: Step.Change, undoing: Bool, keepsRecord: Bool) throws
        -> Step.Change
    {
        let replaced = change.replaced
        let unreadable = UndoProblem(undoing: undoing, reason: .unreadable)
        switch (change.to, change.from) {
        case (.files(let path), nil):
            let item = try moveIntoBin(path, now: Date())
            return Step.Change(from: .files(path), to: item.place, replaced: replaced)
        case (.files(let path), .bin(let id, let record)?):
            let item =
                keepsRecord
                ? try moveIntoBin(path, as: record, id: id)
                : try moveIntoBin(path, now: Date(), id: id)
            return Step.Change(from: .files(path), to: item.place, replaced: replaced)
        case (.files(let path), .files(let back)?):
            guard let name = back.name, let old = path.name else {
                throw unreadable
            }
            try place(path.url(in: root), to: back.url(in: root), named: name, goneName: old)
            return Step.Change(from: .files(path), to: .files(back), replaced: replaced)
        case (.bin(let id, let record), .files(let back)?):
            let item = try moveOutOfBin(id, named: record.name, to: back)
            return Step.Change(from: item.place, to: .files(back), replaced: replaced)
        case (.bin, _):
            throw unreadable
        }
    }

    /// Takes the item out of the bin to exactly `path`. Returns it as it was in
    /// the bin.
    private func moveOutOfBin(_ id: UUID, named name: String, to path: FilePath) throws
        -> BinItem
    {
        guard let item = bin.item(id), let placed = path.name else {
            throw FileOperationError.gone(name)
        }
        try place(item.url, to: path.url(in: root), named: placed, goneName: item.name)
        try? FileManager.default.removeItem(at: item.directory)
        return item
    }

    /// Brings the clipboard up to date and drops the changed folders' totals.
    private func finish(_ done: [Step.Change], folders: [FilePath]) async {
        var changed = folders.map { $0.url(in: root) }
        for change in done {
            if case .files(let path) = change.from {
                changed.append(path.url(in: root))
                if case .files(let new) = change.to {
                    updateClipboard { $0.following(path, to: new) }
                } else {
                    updateClipboard { $0.dropping(within: path) }
                }
            }
            if case .files(let path) = change.to { changed.append(path.url(in: root)) }
        }
        await forget(changed)
    }

    // MARK: Checks

    /// Why making the folders and then reversing `changes`, in order, would
    /// fail; `nil` when it wouldn't. Each is checked as the ones before it
    /// would leave things, before any is made.
    private func problem(reversing changes: [Step.Change], making folders: [FilePath])
        -> UndoProblem.Reason?
    {
        var plan = Plan(root: root)
        for folder in folders {
            guard let name = folder.name, let parent = folder.parent else { return .unreadable }
            if let reason = plan.problem(placingIn: parent) { return reason }
            // A folder already there with exactly this name is used.
            if let existing = plan.names(in: parent).first(where: { NameRules.sameName($0, name) })
            {
                guard existing == name, plan.isFolder(folder) == true else {
                    return .taken(name, in: parent)
                }
            } else {
                plan.make(folder)
            }
        }
        var taken: Set<UUID> = []
        for change in changes {
            let source: URL
            switch change.to {
            case .files(let path):
                guard let url = plan.existing(path) else {
                    return .gone(path.name ?? "", in: path.parent ?? .root)
                }
                source = url
                plan.vacate(path)
            case .bin(let id, let record):
                guard !taken.contains(id), let item = bin.item(id) else {
                    return .notInBin(record.original.last ?? record.name)
                }
                source = item.url
                taken.insert(id)
            }
            switch change.from {
            case .files(let back)?:
                guard let name = back.name, let folder = back.parent else { return .unreadable }
                if let reason = plan.problem(placingIn: folder) { return reason }
                if plan.names(in: folder).contains(where: { NameRules.sameName($0, name) }) {
                    return .taken(name, in: folder)
                }
                plan.place(back, from: source)
            case .bin(let id, _)?:
                // Going back under its ID, which nothing else in the bin can have.
                guard case .files = change.to,
                    !FileManager.default.fileExists(
                        atPath: bin.directory(for: id).path(percentEncoded: false))
                else { return .unreadable }
            case nil:
                guard case .files = change.to else { return .unreadable }
            }
        }
        return nil
    }
}

extension [Step.Change] {
    /// The paths these changes took items from.
    var vacated: [FilePath] {
        return compactMap { change in
            if case .files(let path) = change.from { return path }
            return nil
        }
    }
}

/// Files as a step's changes would leave them, for checking each change before
/// any is made.
private struct Plan {
    let root: URL

    /// Paths vacated (`nil`) or filled from somewhere, newest last.
    private var changes: [(path: FilePath, url: URL?)] = []

    init(root: URL) {
        self.root = root
    }

    mutating func vacate(_ path: FilePath) {
        changes.append((path, nil))
    }

    mutating func place(_ path: FilePath, from url: URL) {
        changes.append((path, url))
    }

    /// Folders that would be made.
    private var made: Set<FilePath> = []

    mutating func make(_ folder: FilePath) {
        made.insert(folder)
    }

    /// Whether a folder would be at `path`; `nil` when nothing would be.
    func isFolder(_ path: FilePath) -> Bool? {
        if made.contains(path) { return true }
        return existing(path).map { FileOperations.kind(at: $0) != .file }
    }

    /// Why nothing could go into `folder`; `nil` when something could.
    func problem(placingIn folder: FilePath) -> UndoProblem.Reason? {
        switch isFolder(folder) {
        case nil: return .folderGone(folder)
        case false?: return .notAFolder(folder)
        case true?: return nil
        }
    }

    /// Where the item at `path` would be on disk; `nil` when nothing would be
    /// there.
    func existing(_ path: FilePath) -> URL? {
        guard let url = url(of: path) else { return nil }
        let exists =
            (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))
            != nil
        return exists ? url : nil
    }

    /// The names that would be in `folder`.
    func names(in folder: FilePath) -> [String] {
        var names: [String] = []
        if let url = existing(folder) {
            names =
                (try? FileManager.default.contentsOfDirectory(
                    atPath: url.path(percentEncoded: false))) ?? []
        }
        for change in changes where change.path.parent == folder {
            if let name = change.path.name, !names.contains(name) { names.append(name) }
        }
        return names.filter { existing(folder.appending($0)) != nil }
    }

    private func url(of path: FilePath) -> URL? {
        for change in changes.reversed() where path.isWithin(change.path) {
            guard let url = change.url else { return nil }
            return path.components.dropFirst(change.path.components.count).reduce(url) {
                $0.appending(path: $1)
            }
        }
        return path.url(in: root)
    }
}
