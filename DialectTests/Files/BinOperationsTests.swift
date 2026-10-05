import Foundation
import Testing

@testable import Dialect

/// Deleting into the bin, restoring from it, and emptying it.
struct BinOperationsTests {
    private let noon = BinTests.noon
    private let day: TimeInterval = 24 * 60 * 60

    // MARK: Deleting

    /// Files, folders and sessions move in whole, with their records and a
    /// folder's view settings.
    @Test func deletesEachKindIntoTheBin() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("scripts/prelude.scm", text: "p")
        let folder = try setup.root.folder("notes")
        try setup.root.file("notes/todo.txt")
        var settings = FolderViewSettings()
        settings.sort = .modified
        try settings.write(to: folder)
        try setup.root.file("demo.dial/main.scm")

        let deleted = try await setup.operations.delete(
            [FilePath("scripts/prelude.scm"), FilePath("notes"), FilePath("demo.dial")], now: noon)
        #expect(deleted.map(\.name) == ["prelude.scm", "notes", "demo.dial"])
        #expect(try setup.names() == ["scripts"])
        #expect(try setup.names("scripts").isEmpty)

        let items = setup.bin.items()
        #expect(Set(items.map(\.name)) == ["prelude.scm", "notes", "demo.dial"])
        let notes = try #require(items.first { $0.name == "notes" })
        #expect(notes.isDirectory)
        #expect(notes.original == FilePath("notes"))
        #expect(notes.deleted == noon)
        #expect(FolderViewSettings.read(at: notes.url) == settings)
        let prelude = try #require(items.first { $0.name == "prelude.scm" })
        #expect(try String(contentsOf: prelude.url, encoding: .utf8) == "p")
        #expect(prelude.original == FilePath("scripts/prelude.scm"))
    }

    /// A link is deleted as the link; its target stays.
    @Test func deletesALinkNotWhatItLeadsTo() async throws {
        let setup = try OperationsSetup()
        let real = try setup.root.file("real.txt", text: "r")
        try FileManager.default.createSymbolicLink(
            at: setup.root.url.appending(path: "link"), withDestinationURL: real)
        _ = try await setup.operations.delete([FilePath("link")])
        #expect(try setup.names() == ["real.txt"])
        let item = try #require(setup.bin.items().first)
        let values = try item.url.resourceValues(forKeys: [.isSymbolicLinkKey])
        #expect(values.isSymbolicLink == true)
    }

    /// The newest item takes the name, and the item holding it is renamed to
    /// the next free number. Names match in any case.
    @Test func renamesTheNamesakeAlreadyInTheBin() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("scripts/draft.scm", text: "1")
        try setup.root.file("lib/draft.scm", text: "2")
        try setup.root.file("Draft.scm", text: "3")
        _ = try await setup.operations.delete([FilePath("scripts/draft.scm")], now: noon)
        _ = try await setup.operations.delete([FilePath("lib/draft.scm")], now: noon + 1)
        #expect(setup.bin.items().map(\.name) == ["draft.scm", "draft 2.scm"])
        _ = try await setup.operations.delete([FilePath("Draft.scm")], now: noon + 2)

        let items = setup.bin.items()
        #expect(items.map(\.name) == ["Draft.scm", "draft 3.scm", "draft 2.scm"])
        #expect(
            try items.map { try String(contentsOf: $0.url, encoding: .utf8) } == ["3", "2", "1"])
    }

    /// Folders and sessions are numbered as the Finder numbers them.
    @Test func numbersFoldersAndSessionsWhole() async throws {
        let setup = try OperationsSetup()
        try setup.root.folder("a/v1.old")
        try setup.root.folder("v1.old")
        try setup.root.folder("a/demo.dial")
        try setup.root.folder("demo.dial")
        _ = try await setup.operations.delete([FilePath("a/v1.old")], now: noon)
        _ = try await setup.operations.delete([FilePath("v1.old")], now: noon + 1)
        _ = try await setup.operations.delete([FilePath("a/demo.dial")], now: noon + 2)
        _ = try await setup.operations.delete([FilePath("demo.dial")], now: noon + 3)
        #expect(
            setup.bin.items().map(\.name) == ["demo.dial", "demo 2.dial", "v1.old", "v1.old 2"])
    }

    @Test func failsToDeleteWhatsGone() async throws {
        let setup = try OperationsSetup()
        await #expect(throws: FileOperationError.gone("draft.scm")) {
            try await setup.operations.delete([FilePath("draft.scm")])
        }
        #expect(setup.bin.isEmpty)
    }

    /// Deleting several items stops at the first failure and reports what was
    /// done.
    @Test func stopsPartWayAndSaysHowFarItGot() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("c.txt")
        await #expect {
            try await setup.operations.delete(
                [FilePath("a.txt"), FilePath("b.txt"), FilePath("c.txt")])
        } throws: { error in
            guard let failure = error as? PartialFailure<BinItem> else { return false }
            return failure.done.map(\.name) == ["a.txt"]
                && failure.underlying as? FileOperationError == .gone("b.txt")
        }
        #expect(try setup.names() == ["c.txt"])
    }

    @Test func forgetsTheTotalsAboveADeletion() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("tree/sub/a.txt", Data(count: 10))
        try setup.root.file("tree/sub/b.txt", Data(count: 5))
        let tree = setup.root.url.appending(path: "tree")
        #expect(await setup.sizes.size(of: tree, modified: nil) == 15)
        _ = try await setup.operations.delete([FilePath("tree/sub/b.txt")])
        #expect(await setup.sizes.size(of: tree, modified: nil) == 10)
    }

    // MARK: Restoring

    @Test func restoresToItsPlace() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("scripts/prelude.scm", text: "p")
        let item = try #require(
            try await setup.operations.delete([FilePath("scripts/prelude.scm")]).first)
        #expect(try await setup.operations.restore(item).path == FilePath("scripts/prelude.scm"))
        #expect(try setup.text("scripts/prelude.scm") == "p")
        #expect(setup.bin.isEmpty)
    }

    /// Restore recreates missing folders.
    @Test func recreatesTheFoldersItWasIn() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("scripts/lib/a.scm")
        let item = try #require(
            try await setup.operations.delete([FilePath("scripts/lib/a.scm")]).first)
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "scripts"))
        #expect(try await setup.operations.restore(item).path == FilePath("scripts/lib/a.scm"))
        #expect(setup.exists("scripts/lib/a.scm"))
    }

    /// Restore treats a session on the path as a folder.
    @Test func restoresIntoASession() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("demo.dial/main.scm", text: "m")
        let item = try #require(
            try await setup.operations.delete([FilePath("demo.dial/main.scm")]).first)
        #expect(try await setup.operations.restore(item).path == FilePath("demo.dial/main.scm"))
    }

    /// A folder matching in another case is reused, and the returned path is
    /// spelled as on disk.
    @Test func restoresIntoAFolderInAnotherCase() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("scripts/a.scm")
        let item = try #require(
            try await setup.operations.delete([FilePath("scripts/a.scm")]).first)
        try FileManager.default.moveItem(
            at: setup.root.url.appending(path: "scripts"),
            to: setup.root.url.appending(path: "Scripts"))
        #expect(try await setup.operations.restore(item).path == FilePath("Scripts/a.scm"))
    }

    /// A taken name gets the deletion date before the extension, then a number
    /// if that's taken too.
    @Test func datesTheNameWhenItsPlaceIsTaken() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes.md", text: "deleted")
        let item = try #require(
            try await setup.operations.delete([FilePath("notes.md")], now: noon).first)
        try setup.root.file("notes.md", text: "new")
        try setup.root.file("notes-2026-10-05.md", text: "dated")
        #expect(try await setup.operations.restore(item).path == FilePath("notes-2026-10-05 2.md"))
        #expect(try setup.text("notes-2026-10-05 2.md") == "deleted")
        #expect(try setup.text("notes.md") == "new")
    }

    @Test func datesFoldersAndSessionsWhole() async throws {
        let setup = try OperationsSetup()
        try setup.root.folder("v1.old")
        try setup.root.folder("demo.dial")
        let items = try await setup.operations.delete(
            [FilePath("v1.old"), FilePath("demo.dial")], now: noon)
        try setup.root.folder("v1.old")
        try setup.root.folder("demo.dial")
        #expect(try await setup.operations.restore(items[0]).path == FilePath("v1.old-2026-10-05"))
        #expect(
            try await setup.operations.restore(items[1]).path == FilePath("demo-2026-10-05.dial"))
    }

    /// When a file has the name of a folder on the path, the folder is
    /// recreated beside it under a dated name, which later restores share.
    @Test func datesAFolderWhenAFileStandsInItsPlace() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/f.txt")
        try setup.root.file("a/g.txt")
        let items = try await setup.operations.delete(
            [FilePath("a/f.txt"), FilePath("a/g.txt")], now: noon)
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "a"))
        try setup.root.file("a", text: "a file")
        #expect(try await setup.operations.restore(items[0]).path == FilePath("a-2026-10-05/f.txt"))
        #expect(try await setup.operations.restore(items[1]).path == FilePath("a-2026-10-05/g.txt"))
        #expect(try setup.text("a") == "a file")
    }

    /// A renamed item restores under its new name.
    @Test func restoresUnderTheNameItHasInTheBin() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("scripts/draft.scm")
        try setup.root.file("draft.scm")
        _ = try await setup.operations.delete([FilePath("scripts/draft.scm")], now: noon)
        _ = try await setup.operations.delete([FilePath("draft.scm")], now: noon + 1)
        let older = try #require(setup.bin.items().last)
        #expect(try await setup.operations.restore(older).path == FilePath("scripts/draft 2.scm"))
    }

    /// An item renamed in the bin since it was listed restores under its
    /// current name.
    @Test func restoresUnderItsNameNowNotAsListed() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("scripts/draft.scm")
        try setup.root.file("draft.scm")
        let listed = try #require(
            try await setup.operations.delete([FilePath("scripts/draft.scm")], now: noon).first)
        _ = try await setup.operations.delete([FilePath("draft.scm")], now: noon + 1)
        #expect(try await setup.operations.restore(listed).path == FilePath("scripts/draft 2.scm"))
    }

    /// An item without a record restores to the root, even before tidying.
    @Test func restoresAnItemFoundWithoutItsRecord() async throws {
        let setup = try OperationsSetup()
        let directory = setup.bin.directory(for: UUID())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("r".utf8).write(to: Bin.item(in: directory))
        let item = try #require(setup.bin.items().first)
        #expect(try await setup.operations.restore(item).path == FilePath("Recovered Item"))
        #expect(try setup.text("Recovered Item") == "r")
        #expect(setup.bin.isEmpty)
    }

    /// Three namesakes deleted in a row, one restored between them: each
    /// restores under the name it then has.
    @Test func followsTheNamingChainThroughARestore() async throws {
        let setup = try OperationsSetup()
        for folder in ["a", "b", "c"] { try setup.root.file("\(folder)/draft.scm", text: folder) }
        let a = try #require(
            try await setup.operations.delete([FilePath("a/draft.scm")], now: noon).first)
        _ = try await setup.operations.delete([FilePath("b/draft.scm")], now: noon + 1)
        // `a`'s is now `draft 2.scm`.
        #expect(try await setup.operations.restore(a).path == FilePath("a/draft 2.scm"))
        _ = try await setup.operations.delete([FilePath("c/draft.scm")], now: noon + 2)
        // `b`'s held the name, so it's renamed to the lowest free number, now 2 again.
        #expect(setup.bin.items().map(\.name) == ["draft.scm", "draft 2.scm"])
        let restored = try await setup.operations.restoreAll().map(\.path)
        #expect(restored == [FilePath("c/draft.scm"), FilePath("b/draft 2.scm")])
        #expect(try setup.text("b/draft 2.scm") == "b")
    }

    /// Restore All stops at the first failure and reports what it restored.
    @Test func restoreAllStopsPartWay() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("locked/a.txt")
        try setup.root.file("open/b.txt")
        _ = try await setup.operations.delete([FilePath("locked/a.txt")], now: noon)
        _ = try await setup.operations.delete([FilePath("open/b.txt")], now: noon + 1)
        let locked = setup.root.url.appending(path: "locked").path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked)
        }
        await #expect {
            try await setup.operations.restoreAll()
        } throws: { error in
            (error as? PartialFailure<Restored>)?.done.map(\.path) == [FilePath("open/b.txt")]
        }
        #expect(setup.bin.items().map(\.name) == ["a.txt"])
    }

    @Test func failsToRestoreWhatsGoneFromTheBin() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        let item = try #require(try await setup.operations.delete([FilePath("a.txt")]).first)
        try await setup.operations.deletePermanently([item])
        await #expect(throws: FileOperationError.gone("a.txt")) {
            try await setup.operations.restore(item).path
        }
    }

    /// Restoring newest first reverses the deletes: `a` returns before `f`,
    /// which goes back into `a/b`, and nothing is dated.
    @Test func restoresAllNewestFirst() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/b/f.txt", text: "f")
        try setup.root.file("a/b/other.txt")
        try setup.root.file("taken.txt", text: "old")
        _ = try await setup.operations.delete([FilePath("a/b/f.txt")], now: noon)
        _ = try await setup.operations.delete([FilePath("a")], now: noon + 1)
        _ = try await setup.operations.delete([FilePath("taken.txt")], now: noon + 2)
        try setup.root.file("taken.txt", text: "new")

        let restored = try await setup.operations.restoreAll().map(\.path)
        #expect(
            restored == [
                FilePath("taken-2026-10-05.txt"), FilePath("a"), FilePath("a/b/f.txt"),
            ])
        #expect(try setup.names("a/b") == ["f.txt", "other.txt"])
        #expect(try setup.text("taken.txt") == "new")
        #expect(setup.bin.isEmpty)
    }

    /// Restoring `f` alone recreates `a/b`; restoring `a` afterwards finds its
    /// name taken and comes back dated.
    @Test func restoresAFolderBesideOneRemadeForItsContents() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/b/f.txt", text: "f")
        try setup.root.file("a/b/other.txt")
        let f = try #require(
            try await setup.operations.delete([FilePath("a/b/f.txt")], now: noon).first)
        let a = try #require(
            try await setup.operations.delete([FilePath("a")], now: noon + 1).first)
        #expect(try await setup.operations.restore(f).path == FilePath("a/b/f.txt"))
        #expect(try await setup.operations.restore(a).path == FilePath("a-2026-10-05"))
        #expect(try setup.names("a/b") == ["f.txt"])
        #expect(try setup.names("a-2026-10-05/b") == ["other.txt"])
    }

    // MARK: Emptying

    @Test func deletesPermanently() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("b.txt")
        let items = try await setup.operations.delete([FilePath("a.txt"), FilePath("b.txt")])
        try await setup.operations.deletePermanently([items[0]])
        #expect(setup.bin.items().map(\.name) == ["b.txt"])
        try await setup.operations.deleteAll()
        #expect(setup.bin.isEmpty)
    }

    /// Deleting permanently moves the item out of the bin in one step before
    /// removing it, so an interrupted removal leaves nothing to recover.
    @Test func deletesPermanentlyByWayOfStaging() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        let item = try #require(try await setup.operations.delete([FilePath("a.txt")]).first)
        try await setup.operations.deletePermanently([item])
        #expect(!FileManager.default.fileExists(atPath: item.directory.path(percentEncoded: false)))
        #expect(setup.staged().isEmpty)
    }

    /// A record whose original path leaves the root restores to the root.
    @Test func neverRestoresOutsideTheRoot() async throws {
        let setup = try OperationsSetup()
        let directory = setup.bin.directory(for: UUID())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try setup.bin.write(
            Bin.Record(name: "x.txt", original: ["..", "x.txt"], deleted: noon), in: directory)
        try Data().write(to: Bin.item(in: directory))
        let item = try #require(setup.bin.items().first)
        #expect(try await setup.operations.restore(item).path == FilePath("x.txt"))
    }

    @Test func removesWhatsExpired() async throws {
        let setup = try OperationsSetup()
        for name in ["old.txt", "recent.txt", "new.txt"] { try setup.root.file(name) }
        _ = try await setup.operations.delete([FilePath("old.txt")], now: noon - 40 * day)
        _ = try await setup.operations.delete([FilePath("recent.txt")], now: noon - 29 * day)
        _ = try await setup.operations.delete([FilePath("new.txt")], now: noon)

        #expect(await setup.operations.removeExpired(now: noon, after: nil) == 0)
        #expect(setup.bin.items().count == 3)
        #expect(await setup.operations.removeExpired(now: noon, after: 30) == 1)
        #expect(setup.bin.items().map(\.name) == ["new.txt", "recent.txt"])
        #expect(await setup.operations.removeExpired(now: noon, after: 1) == 1)
        #expect(setup.bin.items().map(\.name) == ["new.txt"])
    }

    /// Removing what's expired also tidies what a crash left.
    @Test func tidiesAsItRemovesWhatsExpired() async throws {
        let setup = try OperationsSetup()
        let directory = setup.bin.directory(for: UUID())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try setup.bin.write(
            Bin.Record(name: "a", original: ["a"], deleted: noon), in: directory)
        #expect(!setup.bin.isEmpty)
        _ = await setup.operations.removeExpired(now: noon, after: nil)
        #expect(setup.bin.isEmpty)
    }
}
