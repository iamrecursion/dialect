import Foundation
import Testing

@testable import Dialect

/// Undo and Redo: each step both ways and back again, the checks that stop
/// them, and the bin's part.
struct UndoTests {
    // MARK: Each kind

    @Test func undoesAndRedoesARename() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/a.txt", text: "a")
        _ = try await setup.operations.rename(FilePath("notes/a.txt"), to: "b.txt")
        try await setup.operations.copy([FilePath("notes/b.txt")])

        #expect(try await setup.operations.undo() == [FilePath("notes/b.txt")])
        #expect(try setup.names("notes") == ["a.txt"])
        // The clipboard follows it, as it follows every rename.
        #expect(setup.clipboard.paths() == [FilePath("notes/a.txt")])

        #expect(try await setup.operations.redo() == [FilePath("notes/a.txt")])
        #expect(try setup.names("notes") == ["b.txt"])
        _ = try await setup.operations.undo()
        #expect(try setup.text("notes/a.txt") == "a")
    }

    /// Only a case change: the item in the way is the one going back.
    @Test func undoesARenameOfCaseOnly() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        _ = try await setup.operations.rename(FilePath("a.txt"), to: "A.txt")
        _ = try await setup.operations.undo()
        #expect(try setup.names() == ["a.txt"])
    }

    /// The incoming item goes back before the replaced one comes out of the bin
    /// into its place.
    @Test func undoesAndRedoesAMoveWithReplace() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "new")
        try setup.root.file("notes/plan.md", text: "plan")
        try setup.root.file("archive/todo.txt", text: "old")
        try await setup.operations.copy([FilePath("notes/todo.txt"), FilePath("notes/plan.md")])
        _ = try await setup.operations.move(
            into: FilePath("archive"), choices: [FilePath("notes/todo.txt"): .replace])

        let left = try await setup.operations.undo()
        #expect(Set(left) == [FilePath("archive/todo.txt"), FilePath("archive/plan.md")])
        #expect(try setup.text("notes/todo.txt") == "new")
        #expect(try setup.text("notes/plan.md") == "plan")
        #expect(try setup.text("archive/todo.txt") == "old")
        #expect(setup.bin.items().isEmpty)
        // An undone Move doesn't refill the clipboard.
        #expect(setup.clipboard.paths().isEmpty)

        _ = try await setup.operations.redo()
        #expect(try setup.names("notes").isEmpty)
        #expect(try setup.text("archive/todo.txt") == "new")
        #expect(setup.bin.items().map(\.name) == ["todo.txt"])
        _ = try await setup.operations.undo()
        #expect(try setup.text("archive/todo.txt") == "old")
        #expect(try setup.text("notes/todo.txt") == "new")
    }

    /// The copies go to the bin and come back from it, and a replaced item
    /// comes back into its place.
    @Test func undoesAndRedoesAPasteWithReplace() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "new")
        try setup.root.file("archive/todo.txt", text: "old")
        try await setup.operations.copy([FilePath("notes/todo.txt")])
        _ = try await setup.operations.paste(
            into: FilePath("archive"), choices: [FilePath("notes/todo.txt"): .replace])

        _ = try await setup.operations.undo()
        #expect(try setup.text("archive/todo.txt") == "old")
        #expect(try setup.text("notes/todo.txt") == "new")
        #expect(setup.bin.items().map(\.name) == ["todo.txt"])

        _ = try await setup.operations.redo()
        #expect(try setup.text("archive/todo.txt") == "new")
        #expect(setup.bin.items().count == 1)
        _ = try await setup.operations.undo()
        #expect(try setup.text("archive/todo.txt") == "old")
    }

    /// Two items with one name, both replacing: each Replace is reversed in
    /// turn, back to the item first in the way.
    @Test func undoesTwoReplacesOfOneName() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "notes")
        try setup.root.file("docs/todo.txt", text: "docs")
        try setup.root.file("archive/todo.txt", text: "old")
        let sources = [FilePath("notes/todo.txt"), FilePath("docs/todo.txt")]
        try await setup.operations.copy(sources)
        _ = try await setup.operations.paste(
            into: FilePath("archive"), choices: [sources[0]: .replace, sources[1]: .replace])
        #expect(try setup.text("archive/todo.txt") == "docs")

        _ = try await setup.operations.undo()
        #expect(try setup.names("archive") == ["todo.txt"])
        #expect(try setup.text("archive/todo.txt") == "old")
        _ = try await setup.operations.redo()
        #expect(try setup.text("archive/todo.txt") == "docs")
        _ = try await setup.operations.undo()
        #expect(try setup.text("archive/todo.txt") == "old")
    }

    @Test(arguments: NewItemKind.allCases)
    func undoesAndRedoesMaking(_ kind: NewItemKind) async throws {
        let setup = try OperationsSetup()
        let made =
            switch kind {
            case .folder: try await setup.operations.createFolder(named: "lib", in: .root)
            case .session: try await setup.operations.createSession(named: "d.dial", in: .root)
            case .file: try await setup.operations.createFile(named: "n.md", in: .root)
            }
        try await setup.operations.copy([made])
        #expect(try await setup.operations.undo() == [made])
        #expect(try setup.names().isEmpty)
        #expect(setup.bin.items().map(\.original) == [made])
        #expect(setup.clipboard.paths().isEmpty)
        _ = try await setup.operations.redo()
        #expect(try setup.names() == [try #require(made.name)])
        #expect(setup.bin.items().isEmpty)
    }

    /// The item goes back into the bin under the same ID each time.
    @Test func undoesADeleteAgainAndAgain() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "t")
        let deleted = try await setup.operations.delete([FilePath("notes/todo.txt")])
        for _ in 0..<3 {
            #expect(try await setup.operations.undo().isEmpty)
            #expect(try setup.text("notes/todo.txt") == "t")
            #expect(setup.bin.items().isEmpty)
            #expect(try await setup.operations.redo() == [FilePath("notes/todo.txt")])
            #expect(try setup.names("notes").isEmpty)
            // Back in under its ID.
            #expect(setup.bin.items().map(\.id) == deleted.map(\.id))
        }
    }

    /// Redo deletes it afresh, so an item deleted long ago doesn't expire at
    /// once.
    @Test func redoesADeleteWithANewDate() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("todo.txt")
        let long = Date().addingTimeInterval(-10 * 86_400)
        _ = try await setup.operations.delete([FilePath("todo.txt")], now: long)
        _ = try await setup.operations.undo()
        _ = try await setup.operations.redo()
        #expect(await setup.operations.removeExpired(after: 1) == 0)
        #expect(setup.bin.items().count == 1)
    }

    /// Undoing a Delete puts the item back at its path, whatever the bin has
    /// renamed it to.
    @Test func undoesADeleteTheBinRenamed() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/notes.md", text: "a")
        try setup.root.file("b/notes.md", text: "b")
        _ = try await setup.operations.delete([FilePath("a/notes.md")])
        let newer = try await setup.operations.delete([FilePath("b/notes.md")])
        try await setup.operations.deletePermanently(newer)
        #expect(setup.bin.items().map(\.name) == ["notes 2.md"])
        // Undoing b's delete finds it gone, and drops it; the next reaches a's.
        await #expect(throws: UndoProblem(undoing: true, reason: .notInBin("notes.md"))) {
            try await setup.operations.undo()
        }
        _ = try await setup.operations.undo()
        #expect(try setup.text("a/notes.md") == "a")
    }

    /// An undone Restore goes back into the bin as it was, under its old name
    /// even when it came back dated.
    @Test func undoesADatedRestore() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes.md", text: "old")
        let deleted = try await setup.operations.delete([FilePath("notes.md")])
        try setup.root.file("notes.md", text: "new")
        let restored = try await setup.operations.restore(deleted[0])
        #expect(restored.path != FilePath("notes.md"))

        #expect(try await setup.operations.undo() == [restored.path])
        #expect(try setup.names() == ["notes.md"])
        let item = try #require(setup.bin.items().first)
        #expect(item.name == "notes.md")
        #expect(item.original == FilePath("notes.md"))
        #expect(item.deleted == deleted[0].deleted)

        _ = try await setup.operations.redo()
        #expect(try setup.text(restored.path.components.joined(separator: "/")) == "old")
    }

    /// A Restore that made folders on the way: Undo removes them, and Redo
    /// makes them again.
    @Test func undoesTheFoldersARestoreMade() async throws {
        let setup = try await restoredIntoMadeFolders()
        #expect(setup.history.read().undo.last?.madeFolders == [FilePath("a"), FilePath("a/b")])
        let left = try await setup.operations.undo()
        #expect(Set(left) == [FilePath("a/b/f.txt"), FilePath("a"), FilePath("a/b")])
        #expect(try setup.names().isEmpty)
        _ = try await setup.operations.redo()
        #expect(try setup.text("a/b/f.txt") == "f")
        _ = try await setup.operations.undo()
        #expect(try setup.names().isEmpty)
    }

    /// Restore All's items sharing the folders it made: they're removed after
    /// both items, and made again before either.
    @Test func undoesTheFoldersARestoreAllMade() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/x.txt", text: "x")
        try setup.root.file("a/b/y.txt", text: "y")
        _ = try await setup.operations.delete([FilePath("a/b/y.txt"), FilePath("a/x.txt")])
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "a"))
        _ = try await setup.operations.restoreAll()
        #expect(try setup.text("a/b/y.txt") == "y")
        _ = try await setup.operations.undo()
        #expect(try setup.names().isEmpty)
        _ = try await setup.operations.redo()
        #expect(try setup.text("a/x.txt") == "x")
        #expect(try setup.text("a/b/y.txt") == "y")
    }

    /// A made folder with something new in it stays, and Redo uses it.
    @Test func keepsAMadeFolderWithSomethingInIt() async throws {
        let setup = try await restoredIntoMadeFolders()
        try setup.root.file("a/b/new.txt")
        _ = try await setup.operations.undo()
        #expect(try setup.names("a/b") == ["new.txt"])
        _ = try await setup.operations.redo()
        #expect(try setup.names("a/b") == ["f.txt", "new.txt"])
    }

    @Test func refusesToMakeAFolderAgainWhereAFileIs() async throws {
        let setup = try await restoredIntoMadeFolders()
        _ = try await setup.operations.undo()
        try setup.root.file("a")
        await #expect(throws: UndoProblem(undoing: false, reason: .taken("a", in: .root))) {
            try await setup.operations.redo()
        }
        #expect(try setup.names() == ["a"])
    }

    /// `a/b/f.txt` deleted, `a` removed, and `f.txt` restored, which made `a`
    /// and `a/b` again.
    private func restoredIntoMadeFolders() async throws -> OperationsSetup {
        let setup = try OperationsSetup()
        try setup.root.file("a/b/f.txt", text: "f")
        let deleted = try await setup.operations.delete([FilePath("a/b/f.txt")])
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "a"))
        _ = try await setup.operations.restore(deleted[0])
        return setup
    }

    /// The bin's names apply: of two namesakes, the older deletion is numbered,
    /// which can be the one an undone Restore sends back.
    @Test func numbersAnOlderNamesakeSentBackToTheBin() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/notes.md", text: "a")
        try setup.root.file("b/notes.md", text: "b")
        let deleted = try await setup.operations.delete([FilePath("a/notes.md")])
        _ = try await setup.operations.restore(deleted[0])
        let restore = try #require(setup.history.read().undo.last)
        _ = try await setup.operations.delete([FilePath("b/notes.md")])
        // Undoing the Restore while b's deletion is in the bin.
        try setup.history.write(History.Stacks(undo: [restore]))
        _ = try await setup.operations.undo()
        let names = setup.bin.items().map { "\($0.name) \($0.original.display)" }
        #expect(names.sorted() == ["notes 2.md /a/notes.md", "notes.md /b/notes.md"])
    }

    /// Restore All is one step; its items go back in reverse, so a folder
    /// restored first takes back what was restored into it.
    @Test func undoesRestoreAll() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/b/f.txt", text: "f")
        _ = try await setup.operations.delete([FilePath("a/b/f.txt")])
        _ = try await setup.operations.delete([FilePath("a")])
        _ = try await setup.operations.restoreAll()
        #expect(try setup.text("a/b/f.txt") == "f")

        _ = try await setup.operations.undo()
        #expect(try setup.names().isEmpty)
        #expect(setup.bin.items().count == 2)
        _ = try await setup.operations.redo()
        #expect(try setup.text("a/b/f.txt") == "f")
        // Then the two deletes, newest first.
        _ = try await setup.operations.undo()
        _ = try await setup.operations.undo()
        _ = try await setup.operations.undo()
        #expect(try setup.text("a/b/f.txt") == "f")
        #expect(setup.bin.items().isEmpty)
    }

    /// A folder renamed, then a file inside it: the stack undoes them in turn.
    @Test func undoesStepsWhosePathsDependOnEachOther() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/a.txt")
        _ = try await setup.operations.rename(FilePath("notes"), to: "docs")
        _ = try await setup.operations.rename(FilePath("docs/a.txt"), to: "b.txt")
        _ = try await setup.operations.undo()
        _ = try await setup.operations.undo()
        #expect(try setup.names("notes") == ["a.txt"])
        _ = try await setup.operations.redo()
        _ = try await setup.operations.redo()
        #expect(try setup.names("docs") == ["b.txt"])
    }

    @Test func doesNothingWithNothingToUndo() async throws {
        let setup = try OperationsSetup()
        #expect(try await setup.operations.undo().isEmpty)
        #expect(try await setup.operations.redo().isEmpty)
    }

    /// A crash between changing the files and writing the history leaves a step
    /// whose check then fails, so it never acts twice.
    @Test func refusesAStepACrashLeftBehind() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "new")
        try setup.root.file("archive/todo.txt", text: "old")
        try await setup.operations.copy([FilePath("notes/todo.txt")])
        _ = try await setup.operations.paste(
            into: FilePath("archive"), choices: [FilePath("notes/todo.txt"): .replace])
        let before = setup.history.read()
        _ = try await setup.operations.undo()
        try setup.history.write(before)

        await #expect(throws: UndoProblem(undoing: true, reason: .notInBin("todo.txt"))) {
            try await setup.operations.undo()
        }
        #expect(try setup.text("archive/todo.txt") == "old")
        #expect(setup.bin.items().count == 1)
    }

    /// The history is on disk, so a relaunch carries on.
    @Test func undoesAcrossARelaunch() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        _ = try await setup.operations.delete([FilePath("a.txt")])
        let relaunched = FileOperations(root: setup.root.url, stores: setup.stores.url)
        _ = try await relaunched.undo()
        #expect(try setup.names() == ["a.txt"])
    }

    /// An ID already in the bin is never taken over or removed.
    @Test func leavesAnItemWithTheSameID() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("b.txt")
        let binned = try await setup.operations.moveIntoBin(FilePath("a.txt"), now: Date())
        let record = Bin.Record(name: "b.txt", original: ["b.txt"], deleted: Date())
        await #expect(throws: (any Error).self) {
            try await setup.operations.moveIntoBin(FilePath("b.txt"), as: record, id: binned.id)
        }
        #expect(setup.bin.item(binned.id) == binned)
        #expect(try setup.names() == ["b.txt"])
    }

    /// A stop part way removes the made folders it left empty, and reports them
    /// for screens to leave.
    @Test func removesTheFoldersAStopLeftEmpty() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/b/x.txt")
        try setup.root.file("c/y.txt")
        _ = try await setup.operations.delete([FilePath("a/b/x.txt")])
        _ = try await setup.operations.delete([FilePath("c/y.txt")])
        for folder in ["a", "c"] {
            try FileManager.default.removeItem(at: setup.root.url.appending(path: folder))
        }
        // y.txt is restored first, so undone last, and nothing can leave `c` once it's locked.
        _ = try await setup.operations.restoreAll()
        let locked = setup.root.url.appending(path: "c")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        do {
            _ = try await setup.operations.undo()
            Issue.record("Undo didn't stop")
        } catch let stopped as UndoStopped {
            #expect(
                Set(stopped.vacated) == [FilePath("a/b/x.txt"), FilePath("a"), FilePath("a/b")])
        }
        #expect(try setup.names() == ["c"])
    }

    // MARK: Changed since

    /// Undo asks before sending to the bin what's changed since the step; the
    /// step stays until it's told to go ahead.
    @Test func asksBeforeBinningAChangedFile() async throws {
        let setup = try OperationsSetup()
        let made = try await setup.operations.createFile(named: "n.md", in: .root)
        try Data("written by the REPL".utf8).write(to: made.url(in: setup.root.url))
        let before = setup.history.read()
        await #expect(throws: UndoChanged(undoing: true, names: ["n.md"])) {
            try await setup.operations.undo()
        }
        #expect(setup.history.read() == before)
        #expect(try setup.names() == ["n.md"])
        _ = try await setup.operations.undo(confirmed: true)
        #expect(try setup.names().isEmpty)
    }

    /// Something new inside a pasted folder counts; a step inside it that was
    /// undone doesn't, though it changed the folder's date.
    @Test func asksWhenAFolderHasSomethingNew() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("scripts/a.scm")
        try setup.root.file("x.txt")
        try setup.root.folder("archive")
        try await setup.operations.copy([FilePath("scripts")])
        _ = try await setup.operations.paste(into: FilePath("archive"), choices: [:])
        try await setup.operations.copy([FilePath("x.txt")])
        _ = try await setup.operations.paste(into: FilePath("archive/scripts"), choices: [:])
        _ = try await setup.operations.undo()
        let step = try #require(setup.history.read().undo.last)

        try setup.root.file("archive/scripts/new.scm")
        await #expect(throws: UndoChanged(undoing: true, names: ["scripts"])) {
            try await setup.operations.undo()
        }
        try FileManager.default.removeItem(
            at: setup.root.url.appending(path: "archive/scripts/new.scm"))
        #expect(setup.history.read().undo.last == step)
        _ = try await setup.operations.undo()
        #expect(try setup.names("archive").isEmpty)
    }

    /// A changed item from an undone Restore goes back into the bin as a new
    /// deletion, so it doesn't expire at once with its changes.
    @Test func binsAChangedRestoreAfresh() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("todo.txt", text: "t")
        let long = Date().addingTimeInterval(-10 * 86_400)
        let deleted = try await setup.operations.delete([FilePath("todo.txt")], now: long)
        _ = try await setup.operations.restore(deleted[0])
        try Data("edited".utf8).write(to: setup.root.url.appending(path: "todo.txt"))
        _ = try await setup.operations.undo(confirmed: true)
        #expect(await setup.operations.removeExpired(after: 1) == 0)
        #expect(setup.bin.items().count == 1)
    }

    /// Two Replaces of one name leave one item, asked about once.
    @Test func asksAboutAnItemOnce() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "notes")
        try setup.root.file("docs/todo.txt", text: "docs")
        try setup.root.file("archive/todo.txt", text: "old")
        let sources = [FilePath("notes/todo.txt"), FilePath("docs/todo.txt")]
        try await setup.operations.copy(sources)
        _ = try await setup.operations.paste(
            into: FilePath("archive"), choices: [sources[0]: .replace, sources[1]: .replace])
        try Data("edited".utf8).write(to: setup.root.url.appending(path: "archive/todo.txt"))
        await #expect(throws: UndoChanged(undoing: true, names: ["todo.txt"])) {
            try await setup.operations.undo()
        }
    }

    /// Redo asks the same way: here, a Delete of a file edited since its undo.
    @Test func asksBeforeRedoingADeleteOfAChangedFile() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("todo.txt", text: "t")
        _ = try await setup.operations.delete([FilePath("todo.txt")])
        _ = try await setup.operations.undo()
        try Data("edited".utf8).write(to: setup.root.url.appending(path: "todo.txt"))
        await #expect(throws: UndoChanged(undoing: false, names: ["todo.txt"])) {
            try await setup.operations.redo()
        }
        _ = try await setup.operations.redo(confirmed: true)
        #expect(try setup.names().isEmpty)
    }

    // MARK: Checks

    /// What a failed check looks like: nothing changed, and the step dropped,
    /// so the next Undo reaches the step before.
    private func expectDropped(
        _ setup: OperationsSetup, _ problem: UndoProblem, names: [String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let before = setup.history.read()
        await #expect(throws: problem, sourceLocation: sourceLocation) {
            try await setup.operations.undo()
        }
        #expect(try setup.names() == names, sourceLocation: sourceLocation)
        #expect(
            setup.history.read().undo == before.undo.dropLast(), sourceLocation: sourceLocation)
        #expect(setup.history.read().redo == before.redo, sourceLocation: sourceLocation)
    }

    /// Every item is checked before any moves.
    @Test func refusesWhenAnItemHasMovedAway() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("archive/a.txt")
        try setup.root.file("archive/b.txt")
        try await setup.operations.copy([FilePath("archive/a.txt"), FilePath("archive/b.txt")])
        _ = try await setup.operations.move(into: .root, choices: [:])
        try FileManager.default.moveItem(
            at: setup.root.url.appending(path: "a.txt"),
            to: setup.root.url.appending(path: "c.txt"))
        try await expectDropped(
            setup, UndoProblem(undoing: true, reason: .gone("a.txt", in: .root)),
            names: ["archive", "b.txt", "c.txt"])
    }

    @Test func refusesWhenTheNameIsTaken() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        _ = try await setup.operations.delete([FilePath("notes/todo.txt")])
        try setup.root.file("notes/Todo.txt")
        try await expectDropped(
            setup,
            UndoProblem(undoing: true, reason: .taken("todo.txt", in: FilePath("notes"))),
            names: ["notes"])
        #expect(setup.bin.items().count == 1)
    }

    /// Unlike Restore, Undo doesn't make the folder again.
    @Test func refusesWhenTheFolderIsGone() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        _ = try await setup.operations.delete([FilePath("notes/todo.txt")])
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "notes"))
        try await expectDropped(
            setup, UndoProblem(undoing: true, reason: .folderGone(FilePath("notes"))), names: [])

        try setup.root.file("notes/todo.txt")
        _ = try await setup.operations.delete([FilePath("notes/todo.txt")])
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "notes"))
        try setup.root.file("notes")
        try await expectDropped(
            setup, UndoProblem(undoing: true, reason: .notAFolder(FilePath("notes"))),
            names: ["notes"])
    }

    /// The bin emptied itself: Undo finds out when tried.
    @Test func refusesWhenTheBinNoLongerHasIt() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("b.txt")
        _ = try await setup.operations.delete([FilePath("a.txt")])
        _ = try await setup.operations.delete([FilePath("b.txt")])
        await setup.operations.removeExpired(now: Date().addingTimeInterval(86_400 * 2), after: 1)
        try await expectDropped(
            setup, UndoProblem(undoing: true, reason: .notInBin("b.txt")), names: [])
        try await expectDropped(
            setup, UndoProblem(undoing: true, reason: .notInBin("a.txt")), names: [])
        #expect(try await setup.operations.undo().isEmpty)
    }

    @Test func refusesARedoTheSameWay() async throws {
        let setup = try OperationsSetup()
        _ = try await setup.operations.createFolder(named: "lib", in: .root)
        _ = try await setup.operations.undo()
        try setup.root.folder("Lib")
        await #expect(throws: UndoProblem(undoing: false, reason: .taken("lib", in: .root))) {
            try await setup.operations.redo()
        }
        #expect(setup.history.read() == History.Stacks())
    }

    /// A failure while acting stops there, keeps what was done, and drops the
    /// step.
    @Test func stopsPartWay() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("locked/b.txt")
        let deleted = try await setup.operations.delete([
            FilePath("locked/b.txt"), FilePath("a.txt"),
        ])
        #expect(deleted.count == 2)
        // Nothing can go into a folder that can't be written.
        let locked = setup.root.url.appending(path: "locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        do {
            _ = try await setup.operations.undo()
            Issue.record("Undo didn't stop")
        } catch let stopped as UndoStopped {
            #expect(stopped.done.map(\.path) == [FilePath("a.txt")])
            // Out of the bin, so nothing in Files was left.
            #expect(stopped.vacated.isEmpty)
        }
        #expect(try setup.names() == ["a.txt", "locked"])
        #expect(setup.history.read() == History.Stacks())
    }
}
