import Foundation
import Testing

@testable import Dialect

/// The undo history's store: what it keeps, and how long it is.
struct HistoryTests {
    private static let record = Bin.Record(
        name: "notes 2.md", original: ["notes", "notes.md"],
        deleted: Date(timeIntervalSinceReferenceDate: 812_345_678.125))

    /// One step of each kind, with each place a change can have.
    static let steps: [Step] = [
        Step(
            kind: .rename,
            changes: [Step.Change(from: .files(FilePath("a.txt")), to: .files(FilePath("b.txt")))]),
        Step(
            kind: .move,
            changes: [
                Step.Change(
                    from: .files(FilePath("archive/todo.txt")),
                    to: .bin(id: UUID(), record: record), replaced: true),
                Step.Change(
                    from: .files(FilePath("notes/todo.txt")),
                    to: .files(FilePath("archive/todo.txt"))),
            ]),
        Step(kind: .paste, changes: [Step.Change(from: nil, to: .files(FilePath("x copy.scm")))]),
        Step(kind: .newFolder, changes: [Step.Change(from: nil, to: .files(FilePath("lib")))]),
        Step(kind: .newSession, changes: [Step.Change(from: nil, to: .files(FilePath("d.dial")))]),
        Step(kind: .newFile, changes: [Step.Change(from: nil, to: .files(FilePath("n.md")))]),
        Step(
            kind: .delete,
            changes: [
                Step.Change(
                    from: .files(FilePath("notes/notes.md")), to: .bin(id: UUID(), record: record))
            ]),
        Step(
            kind: .restore,
            changes: [
                Step.Change(
                    from: .bin(id: UUID(), record: record), to: .files(FilePath("notes/notes.md")))
            ]),
    ]

    private func history(_ setup: OperationsSetup) -> History {
        return History(url: FilesStores.history(in: setup.stores.url))
    }

    @Test func keepsEveryKindOfStep() throws {
        let setup = try OperationsSetup()
        let history = history(setup)
        let stacks = History.Stacks(undo: Self.steps, redo: Self.steps.reversed())
        try history.write(stacks)
        #expect(history.read() == stacks)
    }

    @Test func isEmptyWhenItCantBeRead() throws {
        let setup = try OperationsSetup()
        let history = history(setup)
        #expect(history.read() == History.Stacks())
        try Data("{\"format\": 1, \"undo\": [{\"kind\": \"juggle\"}]}".utf8).write(to: history.url)
        #expect(history.read() == History.Stacks())

        // A path reaching outside the root.
        let step = Step(
            kind: .rename,
            changes: [
                Step.Change(
                    from: .files(FilePath(components: ["..", "x"])), to: .files(FilePath("y")))
            ])
        try JSONEncoder().encode(History.Stacks(undo: [step])).write(to: history.url)
        #expect(history.read() == History.Stacks())
    }

    /// A new step clears what could be redone, and the oldest go past the
    /// limit.
    @Test func recordingTrimsTheOldestAndClearsRedo() {
        var stacks = History.Stacks(undo: Array(Self.steps[0..<3]), redo: [Self.steps[3]])
        stacks.record(Self.steps[4], limit: 3)
        #expect(stacks.undo == [Self.steps[1], Self.steps[2], Self.steps[4]])
        #expect(stacks.redo.isEmpty)
    }

    /// Shortening drops the oldest: those furthest back in Undo first, then the
    /// last Redo would reach.
    @Test func shorteningDropsTheOldest() {
        let full = History.Stacks(
            undo: Array(Self.steps[0..<3]), redo: [Self.steps[4], Self.steps[3]])
        #expect(full.excess(over: 5) == 0)
        #expect(full.excess(over: 2) == 3)

        var stacks = full
        stacks.trim(to: 2)
        #expect(stacks.undo.isEmpty)
        #expect(stacks.redo == [Self.steps[4], Self.steps[3]])

        stacks = full
        stacks.trim(to: 1)
        #expect(stacks.redo == [Self.steps[3]])
    }

    @Test func trimsWhenTheSettingIsShortened() async throws {
        let setup = try OperationsSetup()
        let history = history(setup)
        try history.write(History.Stacks(undo: Self.steps))
        try await setup.operations.trimHistory(to: 3)
        #expect(history.read().undo == Array(Self.steps.suffix(3)))
    }

    @Test func undoHistorySetting() {
        let name = "HistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(FileSettings.undoHistory(in: defaults) == 20)
        defaults.set(50, forKey: FileSettings.undoHistoryKey)
        #expect(FileSettings.undoHistory(in: defaults) == 50)
        #expect(FileSettings.undoHistoryChoices == [20, 50, 100])
        #expect(
            FileSettings.shorteningNote(dropping: 1)
                == "The oldest step will be dropped and can't then be undone.")
        #expect(
            FileSettings.shorteningNote(dropping: 30)
                == "The oldest 30 steps will be dropped and can't then be undone.")
    }

    // MARK: Recording

    /// Each item that undoing sends to the bin is recorded with its signature.
    @Test func signsWhatUndoWouldBin() async throws {
        let setup = try OperationsSetup()
        let made = try await setup.operations.createFile(named: "n.md", in: .root)
        let change = try #require(setup.history.read().undo.last?.changes.first)
        #expect(change.signature != nil)
        #expect(change.signature == setup.operations.signature(of: made))
        _ = try await setup.operations.rename(made, to: "m.md")
        #expect(setup.history.read().undo.last?.changes.first?.signature == nil)
    }

    /// A folder's signature covers what's in it, by relative path, and gives up
    /// past the limit.
    @Test func signsAFoldersContents() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("scripts/a.scm", text: "a")
        try setup.root.file("scripts/lib/b.scm", text: "b")
        let scripts = FilePath("scripts")
        let first = setup.operations.signature(of: scripts)
        #expect(first != nil)
        #expect(setup.operations.signature(of: scripts) == first)
        try setup.root.file("scripts/lib/c.scm")
        #expect(setup.operations.signature(of: scripts) != first)
        #expect(setup.operations.signature(of: scripts, limit: 3) == nil)
    }

    @Test func recordsMaking() async throws {
        let setup = try OperationsSetup()
        let folder = try await setup.operations.createFolder(named: "lib", in: .root)
        let session = try await setup.operations.createSession(named: "d.dial", in: folder)
        let file = try await setup.operations.createFile(named: "n.md", in: folder)
        #expect(
            setup.history.read().undo.map(\.unsigned) == [
                Step(kind: .newFolder, changes: [Step.Change(from: nil, to: .files(folder))]),
                Step(kind: .newSession, changes: [Step.Change(from: nil, to: .files(session))]),
                Step(kind: .newFile, changes: [Step.Change(from: nil, to: .files(file))]),
            ])
    }

    /// A new step clears what could be redone; a rename to the same name isn't
    /// a step.
    @Test func recordsRenaming() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/a.txt")
        try setup.history.write(History.Stacks(redo: [Self.steps[0]]))
        _ = try await setup.operations.rename(FilePath("notes/a.txt"), to: "a.txt")
        #expect(setup.history.read().undo.isEmpty)
        _ = try await setup.operations.rename(FilePath("notes/a.txt"), to: "b.txt")
        #expect(
            setup.history.read()
                == History.Stacks(undo: [
                    Step(
                        kind: .rename,
                        changes: [
                            Step.Change(
                                from: .files(FilePath("notes/a.txt")),
                                to: .files(FilePath("notes/b.txt")))
                        ])
                ]))
    }

    /// Several items are one step, and a delete that stopped records what it
    /// did.
    @Test func recordsDeleting() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("c.txt")
        let paths = [FilePath("a.txt"), FilePath("c.txt")]
        let deleted = try await setup.operations.delete(paths)
        #expect(
            setup.history.read().undo == [
                Step(
                    kind: .delete,
                    changes: zip(paths, deleted).map {
                        Step.Change(from: .files($0), to: $1.place)
                    })
            ])

        try setup.root.file("d.txt")
        _ = try? await setup.operations.delete([FilePath("d.txt"), FilePath("gone.txt")])
        let step = try #require(setup.history.read().undo.last)
        #expect(step.changes.map(\.path) == [FilePath("d.txt")])
    }

    @Test func recordsRestoring() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("b.txt")
        let deleted = try await setup.operations.delete([FilePath("a.txt"), FilePath("b.txt")])
        let restored = try await setup.operations.restore(deleted[0])
        #expect(
            setup.history.read().undo.last?.unsigned
                == Step(
                    kind: .restore,
                    changes: [Step.Change(from: deleted[0].place, to: .files(restored.path))]))
        let all = try await setup.operations.restoreAll()
        #expect(setup.history.read().undo.last?.changes.count == 1)
        #expect(setup.history.read().undo.last?.changes.first?.to == .files(all[0].path))
    }

    /// Replace's item goes to the bin before the incoming one takes its place;
    /// what Paste skips, and what Move leaves where it was, aren't changes.
    @Test func recordsPastingAndMoving() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt", text: "new")
        try setup.root.file("notes/plan.md")
        try setup.root.file("notes/skip.txt")
        try setup.root.file("todo.txt", text: "old")
        try setup.root.file("skip.txt")
        let sources = [FilePath("notes/todo.txt"), FilePath("notes/plan.md"), FilePath("skip.txt")]
        try await setup.operations.copy(sources + [FilePath("notes/skip.txt")])
        let pasted = try await setup.operations.paste(
            into: .root,
            choices: [FilePath("notes/todo.txt"): .replace, FilePath("notes/skip.txt"): .skip])
        let replaced = try #require(pasted[0].replaced)
        #expect(
            setup.history.read().undo.last?.unsigned
                == Step(
                    kind: .paste,
                    changes: [
                        Step.Change(
                            from: .files(FilePath("todo.txt")), to: replaced.place, replaced: true),
                        Step.Change(from: nil, to: .files(FilePath("todo.txt"))),
                        Step.Change(from: nil, to: .files(FilePath("plan.md"))),
                        Step.Change(from: nil, to: .files(FilePath("skip copy.txt"))),
                    ]))

        try setup.root.folder("archive")
        try await setup.operations.copy([FilePath("notes/plan.md"), FilePath("archive")])
        _ = try await setup.operations.move(into: .root, choices: [:])
        #expect(
            setup.history.read().undo.last
                == Step(
                    kind: .move,
                    changes: [
                        Step.Change(
                            from: .files(FilePath("notes/plan.md")),
                            to: .files(FilePath("plan 2.md")))
                    ]))
    }

    @Test func recordsAMoveThatStopped() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("c.txt")
        try setup.root.file("locked/d.txt")
        try setup.root.folder("archive")
        let locked = setup.root.url.appending(path: "locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        try await setup.operations.copy([FilePath("c.txt"), FilePath("locked/d.txt")])
        _ = try? await setup.operations.move(into: FilePath("archive"), choices: [:])
        #expect(
            setup.history.read().undo
                == [
                    Step(
                        kind: .move,
                        changes: [
                            Step.Change(
                                from: .files(FilePath("c.txt")),
                                to: .files(FilePath("archive/c.txt")))
                        ])
                ])
    }

    /// Copy and Delete Permanently aren't steps, and leave the history as it
    /// was, redo included.
    @Test func leavesTheHistoryForCopyAndDeletePermanently() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("b.txt")
        try setup.root.file("c.txt")
        let stacks = History.Stacks(undo: [Self.steps[0]], redo: [Self.steps[1]])
        try setup.history.write(stacks)
        try await setup.operations.copy([FilePath("a.txt")])
        let binned = try await setup.operations.moveIntoBin(FilePath("b.txt"), now: Date())
        _ = try await setup.operations.moveIntoBin(FilePath("c.txt"), now: Date())
        try await setup.operations.deletePermanently([binned])
        try await setup.operations.deleteAll()
        #expect(setup.history.read() == stacks)
    }
}

extension Step {
    /// Without the signatures, which tests don't spell out.
    var unsigned: Step {
        var step = self
        for index in step.changes.indices { step.changes[index].signature = nil }
        return step
    }
}
