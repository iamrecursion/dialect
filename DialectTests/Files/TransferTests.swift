import Foundation
import Testing

@testable import Dialect

/// Paste and Move: what they do with the clipboard's items, the names they
/// choose, and clashes.
struct TransferTests {
    // MARK: Paste

    /// Files, folders and sessions are copied whole, by way of staging, and the
    /// clipboard keeps them for another Paste.
    @Test func pastesEachKind() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "t")
        let folder = try setup.root.folder("scripts/lib")
        try setup.root.file("scripts/lib/a.scm", text: "a")
        var settings = FolderViewSettings()
        settings.sort = .size
        try settings.write(to: folder)
        try setup.root.file("demo.dial/main.scm", text: "m")
        try setup.root.folder("archive")
        let copied = [FilePath("notes/todo.txt"), FilePath("scripts/lib"), FilePath("demo.dial")]
        try await setup.operations.copy(copied)

        let pasted = try await setup.operations.paste(into: FilePath("archive"), choices: [:])
        #expect(
            pasted == [
                Transfer(source: copied[0], placed: FilePath("archive/todo.txt"), replaced: nil),
                Transfer(source: copied[1], placed: FilePath("archive/lib"), replaced: nil),
                Transfer(source: copied[2], placed: FilePath("archive/demo.dial"), replaced: nil),
            ])
        #expect(try setup.text("archive/todo.txt") == "t")
        #expect(try setup.text("archive/lib/a.scm") == "a")
        #expect(try setup.text("archive/demo.dial/main.scm") == "m")
        #expect(
            FolderViewSettings.read(at: setup.root.url.appending(path: "archive/lib")) == settings)
        #expect(try setup.text("notes/todo.txt") == "t")
        #expect(setup.staged().isEmpty)
        #expect(setup.clipboard.paths() == copied)
    }

    /// Beside the original, a copy is named as the Finder names one, without
    /// asking.
    @Test func pastesBesideTheOriginalAsACopy() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "t")
        try await setup.operations.copy([FilePath("notes/todo.txt")])
        #expect(try await setup.operations.clashes(.paste, into: FilePath("notes")).isEmpty)
        _ = try await setup.operations.paste(into: FilePath("notes"), choices: [:])
        _ = try await setup.operations.paste(into: FilePath("notes"), choices: [:])
        #expect(try setup.names("notes") == ["todo copy 2.txt", "todo copy.txt", "todo.txt"])
    }

    /// The copy is made in staging first, so it never copies into itself.
    @Test func pastesIntoAFolderInsideTheCopy() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("scripts/lib/a.scm")
        try await setup.operations.copy([FilePath("scripts")])
        _ = try await setup.operations.paste(into: FilePath("scripts/lib"), choices: [:])
        #expect(try setup.names("scripts/lib") == ["a.scm", "scripts"])
        #expect(try setup.names("scripts/lib/scripts/lib") == ["a.scm"])
    }

    @Test func copiesALinkAsTheLink() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("target.txt")
        try setup.root.folder("archive")
        try FileManager.default.createSymbolicLink(
            atPath: setup.root.url.appending(path: "link").path(percentEncoded: false),
            withDestinationPath: "target.txt")
        try await setup.operations.copy([FilePath("link")])
        _ = try await setup.operations.paste(into: FilePath("archive"), choices: [:])
        let values = try setup.root.url.appending(path: "archive/link").resourceValues(forKeys: [
            .isSymbolicLinkKey
        ])
        #expect(values.isSymbolicLink == true)
    }

    // MARK: Clashes

    private func clashSetup() async throws -> OperationsSetup {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "new")
        try setup.root.file("notes/plan.md", text: "new plan")
        try setup.root.file("notes/fresh.txt")
        try setup.root.file("todo.txt", text: "old")
        try setup.root.file("Plan.md", text: "old plan")
        try await setup.operations.copy([
            FilePath("notes/todo.txt"), FilePath("notes/plan.md"), FilePath("notes/fresh.txt"),
        ])
        return setup
    }

    @Test func listsClashesInOrder() async throws {
        let setup = try await clashSetup()
        let clashes = try await setup.operations.clashes(.paste, into: .root)
        #expect(
            clashes == [
                Clash(source: FilePath("notes/todo.txt"), existing: "todo.txt", canReplace: true),
                Clash(source: FilePath("notes/plan.md"), existing: "Plan.md", canReplace: true),
            ])
    }

    @Test func keepsBothOrSkips() async throws {
        let setup = try await clashSetup()
        let pasted = try await setup.operations.paste(
            into: .root,
            choices: [FilePath("notes/todo.txt"): .keepBoth, FilePath("notes/plan.md"): .skip])
        #expect(pasted.map(\.placed) == [FilePath("todo 2.txt"), nil, FilePath("fresh.txt")])
        #expect(try setup.text("todo.txt") == "old")
        #expect(try setup.text("todo 2.txt") == "new")
        #expect(try setup.text("Plan.md") == "old plan")
        #expect(try setup.names() == ["Plan.md", "fresh.txt", "notes", "todo 2.txt", "todo.txt"])
    }

    /// Replace sends the item in the way to the bin, where it can be restored.
    @Test func replacesIntoTheBin() async throws {
        let setup = try await clashSetup()
        let pasted = try await setup.operations.paste(
            into: .root,
            choices: [FilePath("notes/todo.txt"): .replace, FilePath("notes/plan.md"): .replace])
        #expect(try setup.text("todo.txt") == "new")
        #expect(try setup.text("plan.md") == "new plan")
        #expect(!(try setup.names()).contains("Plan.md"))
        let binned = setup.bin.items()
        #expect(Set(binned.map(\.name)) == ["todo.txt", "Plan.md"])
        #expect(pasted.compactMap(\.replaced?.name) == ["todo.txt", "Plan.md"])
        let old = try #require(binned.first { $0.name == "todo.txt" })
        #expect(try String(contentsOf: old.url, encoding: .utf8) == "old")
    }

    /// A clash that wasn't asked about keeps both, which never loses anything;
    /// a Replace whose item has gone just places the incoming one.
    @Test func actsOnWhatIsThereNow() async throws {
        let setup = try await clashSetup()
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "todo.txt"))
        try setup.root.file("fresh.txt", text: "made meanwhile")
        let pasted = try await setup.operations.paste(
            into: .root,
            choices: [FilePath("notes/todo.txt"): .replace, FilePath("notes/plan.md"): .skip])
        #expect(pasted.map(\.placed) == [FilePath("todo.txt"), nil, FilePath("fresh 2.txt")])
        #expect(pasted.allSatisfy { $0.replaced == nil })
        #expect(try setup.text("fresh.txt") == "made meanwhile")
        #expect(setup.bin.items().isEmpty)
    }

    /// A source gone since Copy is skipped and dropped.
    @Test func skipsAMissingSource() async throws {
        let setup = try await clashSetup()
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "notes/plan.md"))
        try setup.root.folder("archive")
        let pasted = try await setup.operations.paste(into: FilePath("archive"), choices: [:])
        #expect(pasted.map(\.source) == [FilePath("notes/todo.txt"), FilePath("notes/fresh.txt")])
        #expect(
            setup.clipboard.paths() == [FilePath("notes/todo.txt"), FilePath("notes/fresh.txt")])
    }

    /// Replace's copy is made before anything goes to the bin, so a failed copy
    /// leaves the item in the way where it was.
    @Test func keepsTheItemInTheWayWhenTheCopyFails() async throws {
        let setup = try await clashSetup()
        // An unreadable source fails to copy.
        let source = setup.root.url.appending(path: "notes/todo.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: source.path)
        }
        try await setup.operations.copy([FilePath("notes/todo.txt")])
        await #expect(throws: (any Error).self) {
            try await setup.operations.paste(
                into: .root, choices: [FilePath("notes/todo.txt"): .replace])
        }
        #expect(try setup.text("todo.txt") == "old")
        #expect(setup.bin.items().isEmpty)
        #expect(setup.staged().isEmpty)
    }

    /// Replacing an item binned something else on the clipboard: it's skipped,
    /// though the incoming item now has its path, and leaves the clipboard.
    @Test func skipsWhatReplaceBinned() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/notes.md", text: "new")
        try setup.root.file("notes.md", text: "old")
        try await setup.operations.copy([FilePath("a/notes.md"), FilePath("notes.md")])
        let pasted = try await setup.operations.paste(
            into: .root, choices: [FilePath("a/notes.md"): .replace])
        #expect(pasted.map(\.source) == [FilePath("a/notes.md")])
        #expect(try setup.names() == ["a", "notes.md"])
        #expect(try setup.text("notes.md") == "new")
        #expect(setup.clipboard.paths() == [FilePath("a/notes.md")])
    }

    /// And what was inside the item Replace binned.
    @Test func skipsWhatWasInsideTheReplacedItem() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("x/a/b.txt", text: "new a's")
        try setup.root.file("a/b.txt", text: "old a's")
        try await setup.operations.copy([FilePath("x/a"), FilePath("a/b.txt")])
        _ = try await setup.operations.paste(
            into: .root, choices: [FilePath("x/a"): .replace])
        #expect(try setup.names() == ["a", "x"])
        #expect(try setup.text("a/b.txt") == "new a's")
    }

    // MARK: Move

    /// One rename: the same file, in its new place, and the clipboard empties.
    @Test func moves() async throws {
        let setup = try OperationsSetup()
        let original = try setup.root.file("notes/todo.txt", text: "t")
        try setup.root.file("scripts/lib/a.scm")
        try setup.root.folder("archive")
        let inode = try FileManager.default.attributesOfItem(atPath: original.path)[
            .systemFileNumber]
        try await setup.operations.copy([FilePath("notes/todo.txt"), FilePath("scripts/lib")])

        let moved = try await setup.operations.move(into: FilePath("archive"), choices: [:])
        #expect(moved.map(\.placed) == [FilePath("archive/todo.txt"), FilePath("archive/lib")])
        #expect(try setup.names("notes").isEmpty)
        #expect(try setup.names("scripts").isEmpty)
        #expect(try setup.names("archive/lib") == ["a.scm"])
        let now = setup.root.url.appending(path: "archive/todo.txt").path
        #expect(
            try FileManager.default.attributesOfItem(atPath: now)[.systemFileNumber] as? Int
                == inode as? Int)
        #expect(setup.clipboard.paths().isEmpty)
    }

    /// Into the folder it's already in, nothing happens, and it still leaves
    /// the clipboard.
    @Test func movesIntoItsOwnFolderAsNothing() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        try await setup.operations.copy([FilePath("notes/todo.txt")])
        #expect(try await setup.operations.clashes(.move, into: FilePath("notes")).isEmpty)
        let moved = try await setup.operations.move(into: FilePath("notes"), choices: [:])
        #expect(moved.map(\.placed) == [FilePath("notes/todo.txt")])
        #expect(try setup.names("notes") == ["todo.txt"])
        #expect(setup.clipboard.paths().isEmpty)
    }

    /// Refused before anything moves.
    @Test func refusesToMoveIntoItself() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.folder("scripts/lib")
        try await setup.operations.copy([FilePath("a.txt"), FilePath("scripts")])
        await #expect(throws: FileOperationError.intoItself("scripts")) {
            try await setup.operations.clashes(.move, into: FilePath("scripts"))
        }
        await #expect(throws: FileOperationError.intoItself("scripts")) {
            try await setup.operations.move(into: FilePath("scripts"), choices: [:])
        }
        await #expect(throws: FileOperationError.intoOwnFolder("scripts")) {
            try await setup.operations.move(into: FilePath("scripts/lib"), choices: [:])
        }
        #expect(try setup.names() == ["a.txt", "scripts"])
        #expect(setup.clipboard.paths() == [FilePath("a.txt"), FilePath("scripts")])
    }

    /// Replace isn't offered for the item holding the one being moved; asked
    /// for anyway, it keeps both.
    @Test func doesNotReplaceWhatHoldsTheMovedItem() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/a/inner.txt")
        try await setup.operations.copy([FilePath("a/a")])
        let clashes = try await setup.operations.clashes(.move, into: .root)
        #expect(clashes == [Clash(source: FilePath("a/a"), existing: "a", canReplace: false)])
        #expect(try await setup.operations.clashes(.paste, into: .root).first?.canReplace == true)

        let moved = try await setup.operations.move(
            into: .root, choices: [FilePath("a/a"): .replace])
        #expect(moved.map(\.placed) == [FilePath("a 2")])
        #expect(try setup.names("a 2") == ["inner.txt"])
        #expect(setup.bin.items().isEmpty)
    }

    @Test func replacesOnMove() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "new")
        try setup.root.file("todo.txt", text: "old")
        try await setup.operations.copy([FilePath("notes/todo.txt")])
        let moved = try await setup.operations.move(
            into: .root, choices: [FilePath("notes/todo.txt"): .replace])
        #expect(moved.first?.replaced?.name == "todo.txt")
        #expect(try setup.text("todo.txt") == "new")
        #expect(try setup.names("notes").isEmpty)
    }

    // MARK: Stopping part way

    /// A Paste that stops says what it did; nothing half-made is left.
    @Test func stopsAPastePartWay() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        let unreadable = try setup.root.file("b.txt")
        try setup.root.folder("archive")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
        }
        try await setup.operations.copy([FilePath("a.txt"), FilePath("b.txt")])
        do {
            _ = try await setup.operations.paste(into: FilePath("archive"), choices: [:])
            Issue.record("Paste didn't stop")
        } catch let partial as PartialFailure<Transfer> {
            #expect(partial.done.map(\.placed) == [FilePath("archive/a.txt")])
        }
        #expect(try setup.names("archive") == ["a.txt"])
        #expect(setup.staged().isEmpty)
    }

    /// A Move that stops takes what it moved off the clipboard and keeps the
    /// rest, so trying again carries on.
    @Test func stopsAMovePartWay() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("c.txt")
        try setup.root.file("locked/d.txt")
        try setup.root.folder("archive")
        // Nothing can leave a folder that can't be written.
        let locked = setup.root.url.appending(path: "locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        try await setup.operations.copy([FilePath("c.txt"), FilePath("locked/d.txt")])
        do {
            _ = try await setup.operations.move(into: FilePath("archive"), choices: [:])
            Issue.record("Move didn't stop")
        } catch let partial as PartialFailure<Transfer> {
            #expect(partial.done.map(\.placed) == [FilePath("archive/c.txt")])
        }
        #expect(setup.clipboard.paths() == [FilePath("locked/d.txt")])
    }

    // MARK: Folder sizes

    /// The destination's total and every source folder's are worked out again,
    /// even where a folder's date hasn't changed to say so.
    @Test func forgetsChangedTotals() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "1234")
        let notes = setup.root.url.appending(path: "notes")
        let archive = try setup.root.folder("archive")
        let date = Date(timeIntervalSince1970: 1_000_000_000)
        func pin() throws {
            for url in [notes, archive] {
                try FileManager.default.setAttributes(
                    [.modificationDate: date], ofItemAtPath: url.path)
            }
        }
        try pin()
        #expect(await setup.sizes.size(of: notes, modified: date) == 4)
        #expect(await setup.sizes.size(of: archive, modified: date) == 0)

        try await setup.operations.copy([FilePath("notes/todo.txt")])
        _ = try await setup.operations.paste(into: FilePath("archive"), choices: [:])
        try pin()
        #expect(await setup.sizes.size(of: archive, modified: date) == 4)

        _ = try await setup.operations.move(
            into: FilePath("archive"),
            choices: [
                FilePath("notes/todo.txt"): .replace
            ])
        try pin()
        #expect(await setup.sizes.size(of: notes, modified: date) == 0)
    }
}
