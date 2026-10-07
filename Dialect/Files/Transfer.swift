import Foundation

/// What Paste or Move did with one item on the clipboard.
struct Transfer: Equatable, Sendable {
    enum Kind: Sendable {
        case paste, move
    }

    let source: FilePath

    /// Where it went: `nil` when skipped, and the source itself when moved into
    /// the folder it was in.
    let placed: FilePath?

    /// The item Replace sent to the bin.
    let replaced: BinItem?
}

/// An item on the clipboard whose name is taken where it's going.
struct Clash: Equatable, Identifiable, Sendable {
    let source: FilePath

    /// The name of the item in the way.
    let existing: String

    /// Replace isn't offered when the item in the way holds the one being
    /// moved, which would go to the bin with it.
    let canReplace: Bool

    var id: FilePath { source }
}

enum ClashChoice: Sendable {
    case keepBoth, replace, skip
}

extension FileOperations {
    /// The clashes Paste or Move into `folder` would meet, in the clipboard's
    /// order. Throws when Move would put something into itself.
    func clashes(_ kind: Transfer.Kind, into folder: FilePath) throws -> [Clash] {
        let sources = clipboard.paths().filter(exists)
        if kind == .move { try refuseIntoItself(sources, folder) }
        let taken = try contents(of: folder)
        return sources.compactMap { source in
            guard let name = source.name, source.parent != folder,
                let existing = taken.first(where: { NameRules.sameName($0, name) })
            else { return nil }
            return Clash(
                source: source, existing: existing,
                canReplace: canReplace(kind, source, folder.appending(existing)))
        }
    }

    /// Copies what the clipboard holds into `folder`, which keeps it. A copy
    /// beside its original is named "notes copy.md"; other clashes go as
    /// `choices` says, and keep both when it doesn't say.
    func paste(into folder: FilePath, choices: [FilePath: ClashChoice]) async throws -> [Transfer] {
        return try await transfer(.paste, into: folder, choices: choices)
    }

    /// Moves what the clipboard holds into `folder`, which empties it.
    func move(into folder: FilePath, choices: [FilePath: ClashChoice]) async throws -> [Transfer] {
        return try await transfer(.move, into: folder, choices: choices)
    }

    private func transfer(
        _ kind: Transfer.Kind, into folder: FilePath, choices: [FilePath: ClashChoice]
    ) async throws -> [Transfer] {
        pruneClipboard()
        let sources = clipboard.paths()
        if kind == .move { try refuseIntoItself(sources, folder) }
        _ = try contents(of: folder)
        var done: [Transfer] = []
        // What Replace sent to the bin, which may hold later sources: the incoming item now has its
        // path, so it can't be told by the path alone.
        var binned: [FilePath] = []
        for source in sources {
            guard exists(source), !binned.contains(where: { source.isWithin($0) }) else {
                continue
            }
            do {
                let transfer = try transfer(kind, source, into: folder, choice: choices[source])
                done.append(transfer)
                if let replaced = transfer.replaced { binned.append(replaced.original) }
            } catch {
                await finish(kind, done, into: folder, stopped: true)
                throw PartialFailure.of(error, after: done)
            }
        }
        await finish(kind, done, into: folder, stopped: false)
        return done
    }

    /// One item, which is there.
    private func transfer(
        _ kind: Transfer.Kind, _ source: FilePath, into folder: FilePath, choice: ClashChoice?
    ) throws -> Transfer {
        guard let name = source.name else { preconditionFailure("Files' root can't be copied") }
        let isDirectory = Self.kind(at: source.url(in: root)).map { $0 != .file } ?? false
        let taken = try contents(of: folder)
        var target = name
        var replacing: FilePath?
        if source.parent == folder {
            if kind == .move { return Transfer(source: source, placed: source, replaced: nil) }
            target = NameNumbering.copyName(for: name, isDirectory: isDirectory, taken: taken)
        } else if let existing = taken.first(where: { NameRules.sameName($0, name) }) {
            let inTheWay = folder.appending(existing)
            switch choice ?? .keepBoth {
            case .skip:
                return Transfer(source: source, placed: nil, replaced: nil)
            case .replace where canReplace(kind, source, inTheWay):
                replacing = inTheWay
            case .replace, .keepBoth:
                target = NameNumbering.nextFree(for: name, isDirectory: isDirectory, taken: taken)
            }
        }

        let placed = folder.appending(target)
        let destination = placed.url(in: root)
        let goneName = Self.displayName(of: folder)
        switch kind {
        case .paste:
            let staging = FilesStores.staging(in: stores)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let staged = staging.appending(path: UUID().uuidString, directoryHint: .notDirectory)
            do {
                try FileManager.default.copyItem(at: source.url(in: root), to: staged)
                let replaced = try place(
                    staged, replacing: replacing, to: destination, named: target,
                    goneName: goneName)
                return Transfer(source: source, placed: placed, replaced: replaced)
            } catch {
                try? FileManager.default.removeItem(at: staged)
                throw error
            }
        case .move:
            let replaced = try place(
                source.url(in: root), replacing: replacing, to: destination, named: target,
                goneName: name)
            return Transfer(source: source, placed: placed, replaced: replaced)
        }
    }

    /// Sends `replacing` to the bin, then places the item. When placing fails,
    /// the replaced item comes back, so the folder never ends up with neither.
    private func place(
        _ url: URL, replacing: FilePath?, to destination: URL, named name: String,
        goneName: String
    ) throws -> BinItem? {
        let replaced = try replacing.map { try moveIntoBin($0, now: Date()) }
        do {
            try place(url, to: destination, named: name, goneName: goneName)
        } catch {
            if let replaced { _ = try? moveOutOfBin(replaced, timeZone: .current) }
            throw error
        }
        return replaced
    }

    /// Brings the clipboard up to date and drops the changed folders' totals.
    /// Paste keeps the clipboard; a Move that finished empties it, and one that
    /// stopped keeps what it didn't move.
    private func finish(
        _ kind: Transfer.Kind, _ done: [Transfer], into folder: FilePath, stopped: Bool
    )
        async
    {
        let replaced = done.compactMap { $0.replaced?.original }
        if kind == .move && !stopped {
            try? clipboard.write([])
        } else {
            let moved = kind == .move ? done.filter { $0.placed != nil }.map(\.source) : []
            updateClipboard { held in
                (replaced + moved).reduce(held) { $0.dropping(within: $1) }
            }
        }
        var changed = [folder.url(in: root)]
        for transfer in done where transfer.placed != nil && kind == .move {
            changed.append(transfer.source.url(in: root))
        }
        record(Self.step(kind, done))
        await forget(changed)
    }

    /// The step for what Paste or Move did: an item Replace sent to the bin
    /// before the one that took its place.
    private static func step(_ kind: Transfer.Kind, _ done: [Transfer]) -> Step {
        var changes: [Step.Change] = []
        for transfer in done {
            guard let placed = transfer.placed, kind == .paste || placed != transfer.source else {
                continue
            }
            if let replaced = transfer.replaced {
                changes.append(
                    Step.Change(from: .files(replaced.original), to: replaced.place, replaced: true)
                )
            }
            let from: Step.Place? = kind == .move ? .files(transfer.source) : nil
            changes.append(Step.Change(from: from, to: .files(placed)))
        }
        return Step(kind: kind == .paste ? .paste : .move, changes: changes)
    }

    /// Move refuses outright when any item would go into itself.
    private func refuseIntoItself(_ sources: [FilePath], _ folder: FilePath) throws {
        for source in sources where folder.isWithin(source) {
            let name = source.name ?? ""
            throw folder == source
                ? FileOperationError.intoItself(name) : FileOperationError.intoOwnFolder(name)
        }
    }

    private func canReplace(_ kind: Transfer.Kind, _ source: FilePath, _ inTheWay: FilePath)
        -> Bool
    {
        return kind == .paste || !source.isWithin(inTheWay)
    }
}
