import Foundation
import Testing

@testable import Dialect

/// Recents: what was opened, newest first, kept in Files' stores and following
/// what Files does to the items.
struct RecentsTests {
    // MARK: The store

    @Test func keepsPathsInItsFile() throws {
        let setup = try OperationsSetup()
        let paths = [FilePath("notes/todo.txt"), FilePath("demo.dial")]
        try setup.recents.write(paths)
        #expect(setup.recents.paths() == paths)

        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: FilesStores.recents(in: setup.stores.url)))
        let record = try #require(json as? [String: Any])
        #expect(record["format"] as? Int == 1)
        #expect(record["items"] as? [[String]] == [["notes", "todo.txt"], ["demo.dial"]])
    }

    /// A damaged file, or one with a path reaching outside the root, reads as
    /// empty.
    @Test func isEmptyWithoutAReadableFile() throws {
        let setup = try OperationsSetup()
        let url = FilesStores.recents(in: setup.stores.url)
        #expect(setup.recents.paths().isEmpty)
        try Data("not json".utf8).write(to: url)
        #expect(setup.recents.paths().isEmpty)
        try Data(#"{"format": 1, "items": [["..", "secret"]]}"#.utf8).write(to: url)
        #expect(setup.recents.paths().isEmpty)
    }

    /// Reading leaves out what's gone without writing, as screens read it off
    /// the actor.
    @Test func readsOnlyWhatIsThere() throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        try setup.root.folder("demo.dial")
        let held = [FilePath("notes/todo.txt"), FilePath("gone.txt"), FilePath("demo.dial")]
        try setup.recents.write(held)

        let items = setup.recents.listing(
            root: setup.root.url, textExtensions: [], showHidden: false, limit: 5
        ).all
        #expect(items.map(\.path) == [FilePath("notes/todo.txt"), FilePath("demo.dial")])
        #expect(items.map(\.kind) == [.text, .session])
        #expect(setup.recents.paths() == held)
    }

    /// Show Last counts what's there, so a gone item doesn't take a place.
    @Test func showsTheFirstFewThatAreThere() throws {
        let setup = try OperationsSetup()
        for name in ["a", "b", "c", "d"] { try setup.root.file("\(name).txt") }
        try setup.recents.write(
            ["a.txt", "gone.txt", "b.txt", "c.txt", "d.txt"].map(FilePath.init))
        let items = setup.recents.listing(
            root: setup.root.url, textExtensions: [], showHidden: false, limit: 3
        ).all
        #expect(items.map(\.path) == ["a.txt", "b.txt", "c.txt"].map(FilePath.init))
    }

    /// Hidden items, and anything in a hidden folder, show only with Show
    /// Hidden on, and stay in the store either way.
    @Test func hidesHiddenItemsUnlessShown() throws {
        let setup = try OperationsSetup()
        try setup.root.file(".secret.scm")
        try setup.root.file(".config/init.scm")
        try setup.root.file("notes/todo.txt")
        let held = ["notes/todo.txt", ".secret.scm", ".config/init.scm"].map(FilePath.init)
        try setup.recents.write(held)

        let hidden = setup.recents.listing(
            root: setup.root.url, textExtensions: [], showHidden: false, limit: 5
        ).all
        #expect(hidden.map(\.path) == [FilePath("notes/todo.txt")])
        let shown = setup.recents.listing(
            root: setup.root.url, textExtensions: [], showHidden: true, limit: 5
        ).all
        #expect(shown.map(\.path) == held)
    }

    // MARK: Recording

    @Test func recordsNewestFirstAndOnce() async throws {
        let setup = try OperationsSetup()
        for name in ["a", "b", "c"] { try setup.root.file("\(name).txt") }
        await setup.operations.recordOpen(FilePath("a.txt"))
        await setup.operations.recordOpen(FilePath("b.txt"))
        await setup.operations.recordOpen(FilePath("c.txt"))
        #expect(setup.recents.paths() == ["c.txt", "b.txt", "a.txt"].map(FilePath.init))
        await setup.operations.recordOpen(FilePath("a.txt"))
        #expect(setup.recents.paths() == ["a.txt", "c.txt", "b.txt"].map(FilePath.init))
    }

    /// The store keeps as many as the longest Show Last.
    @Test func keepsTheLongestShowLast() async throws {
        let setup = try OperationsSetup()
        let count = Recents.capacity + 3
        for index in 0..<count {
            try setup.root.file("f\(index).txt")
            await setup.operations.recordOpen(FilePath("f\(index).txt"))
        }
        let held = setup.recents.paths()
        #expect(held.count == Recents.capacity)
        #expect(held.first == FilePath("f\(count - 1).txt"))
        #expect(Recents.capacity == RecentsSettings.showLastChoices.max())
    }

    @Test func recordingDropsWhatIsGone() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("b.txt")
        try setup.recents.write([FilePath("gone.txt"), FilePath("a.txt")])
        await setup.operations.recordOpen(FilePath("b.txt"))
        #expect(setup.recents.paths() == [FilePath("b.txt"), FilePath("a.txt")])
    }

    @Test func hideRemovesAnItem() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("b.txt")
        await setup.operations.recordOpen(FilePath("a.txt"))
        await setup.operations.recordOpen(FilePath("b.txt"))
        try await setup.operations.hideRecent(FilePath("a.txt"))
        #expect(setup.recents.paths() == [FilePath("b.txt")])
    }

    /// Recents is in the stores, so another launch finds it.
    @Test func persists() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        await setup.operations.recordOpen(FilePath("a.txt"))
        let relaunched = FileOperations(root: setup.root.url, stores: setup.stores.url)
        #expect(relaunched.recents.paths() == [FilePath("a.txt")])
    }

    // MARK: Pins

    /// Pins stay at the top, newest opened first, and don't count toward Show
    /// Last.
    @Test func pinsStayAtTheTopInTheirOwnOrder() async throws {
        let setup = try OperationsSetup()
        for name in ["a", "b", "c", "d", "e"] {
            try setup.root.file("\(name).txt")
            await setup.operations.recordOpen(FilePath("\(name).txt"))
        }
        try await setup.operations.pin(FilePath("b.txt"))
        try await setup.operations.pin(FilePath("d.txt"))

        func listing() -> Recents.Listing {
            return setup.recents.listing(
                root: setup.root.url, textExtensions: [], showHidden: false, limit: 2)
        }
        #expect(listing().pinned.map(\.path) == ["d.txt", "b.txt"].map(FilePath.init))
        #expect(listing().recent.map(\.path) == ["e.txt", "c.txt"].map(FilePath.init))

        await setup.operations.recordOpen(FilePath("b.txt"))
        #expect(listing().pinned.map(\.path) == ["b.txt", "d.txt"].map(FilePath.init))
        #expect(listing().recent.map(\.path) == ["e.txt", "c.txt"].map(FilePath.init))

        try await setup.operations.unpin(FilePath("b.txt"))
        #expect(listing().pinned.map(\.path) == [FilePath("d.txt")])
        #expect(listing().recent.map(\.path) == ["b.txt", "e.txt"].map(FilePath.init))
    }

    /// A pin is never pushed out by newer opens.
    @Test func keepsPinsBeyondTheCapacity() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("pinned.txt")
        await setup.operations.recordOpen(FilePath("pinned.txt"))
        try await setup.operations.pin(FilePath("pinned.txt"))
        for index in 0..<(Recents.capacity + 3) {
            try setup.root.file("f\(index).txt")
            await setup.operations.recordOpen(FilePath("f\(index).txt"))
        }
        let held = setup.recents.held()
        #expect(held.pinned == [FilePath("pinned.txt")])
        #expect(held.paths.contains(FilePath("pinned.txt")))
        #expect(held.paths.count == Recents.capacity + 1)
    }

    @Test func allowsThreePins() async throws {
        let setup = try OperationsSetup()
        for name in ["a", "b", "c", "d"] {
            try setup.root.file("\(name).txt")
            await setup.operations.recordOpen(FilePath("\(name).txt"))
        }
        for name in ["a", "b", "c"] { try await setup.operations.pin(FilePath("\(name).txt")) }
        await #expect(throws: RecentsError.tooManyPins) {
            try await setup.operations.pin(FilePath("d.txt"))
        }
        #expect(Recents.pinLimit == 3)
        #expect(setup.recents.held().pinned.count == 3)
    }

    /// A hidden item that's pinned is listed whatever Show Hidden says, as it
    /// counts toward the pin limit.
    @Test func listsHiddenPins() async throws {
        let setup = try OperationsSetup()
        try setup.root.file(".config/init.scm")
        try setup.root.file(".secret.scm")
        await setup.operations.recordOpen(FilePath(".secret.scm"))
        await setup.operations.recordOpen(FilePath(".config/init.scm"))
        try await setup.operations.pin(FilePath(".config/init.scm"))
        let listing = setup.recents.listing(
            root: setup.root.url, textExtensions: [], showHidden: false, limit: 5)
        #expect(listing.pinned.map(\.path) == [FilePath(".config/init.scm")])
        #expect(listing.recent.isEmpty)
    }

    @Test func knowsWhatsHidden() {
        #expect(Recents.isHidden(FilePath(".secret.scm")))
        #expect(Recents.isHidden(FilePath(".config/init.scm")))
        #expect(!Recents.isHidden(FilePath("notes/todo.txt")))
    }

    /// Hiding a pinned item unpins it too.
    @Test func hidingUnpins() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        await setup.operations.recordOpen(FilePath("a.txt"))
        try await setup.operations.pin(FilePath("a.txt"))
        try await setup.operations.hideRecent(FilePath("a.txt"))
        #expect(setup.recents.held() == Recents.Held())
    }

    /// Pins follow renames and leave with deletes, as the rest do.
    @Test func pinsFollowFiles() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        await setup.operations.recordOpen(FilePath("notes/todo.txt"))
        try await setup.operations.pin(FilePath("notes/todo.txt"))
        _ = try await setup.operations.rename(FilePath("notes"), to: "Notes")
        #expect(setup.recents.held().pinned == [FilePath("Notes/todo.txt")])
        _ = try await setup.operations.delete([FilePath("Notes")])
        #expect(setup.recents.held() == Recents.Held())
    }

    /// A file written before pins reads with none.
    @Test func readsAFileWithoutPins() throws {
        let setup = try OperationsSetup()
        try Data(#"{"format": 1, "items": [["a.txt"]]}"#.utf8).write(
            to: FilesStores.recents(in: setup.stores.url))
        #expect(setup.recents.held() == Recents.Held(paths: [FilePath("a.txt")]))
    }

    // MARK: Following Files

    @Test func followsARename() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        await setup.operations.recordOpen(FilePath("notes/todo.txt"))
        _ = try await setup.operations.rename(FilePath("notes"), to: "Notes")
        #expect(setup.recents.paths() == [FilePath("Notes/todo.txt")])
        _ = try await setup.operations.rename(FilePath("Notes/todo.txt"), to: "tasks.txt")
        #expect(setup.recents.paths() == [FilePath("Notes/tasks.txt")])
    }

    /// Undo and Redo move items too.
    @Test func followsUndoAndRedo() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("todo.txt")
        await setup.operations.recordOpen(FilePath("todo.txt"))
        _ = try await setup.operations.rename(FilePath("todo.txt"), to: "tasks.txt")
        _ = try await setup.operations.undo()
        #expect(setup.recents.paths() == [FilePath("todo.txt")])
        _ = try await setup.operations.redo()
        #expect(setup.recents.paths() == [FilePath("tasks.txt")])
    }

    /// Move follows the items, where the clipboard empties.
    @Test func followsAMove() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        try setup.root.folder("archive")
        await setup.operations.recordOpen(FilePath("notes/todo.txt"))
        try await setup.operations.copy([FilePath("notes")])
        _ = try await setup.operations.move(into: FilePath("archive"), choices: [:])
        #expect(setup.recents.paths() == [FilePath("archive/notes/todo.txt")])
    }

    /// Undoing a Move with Replace brings the incoming item back where it was;
    /// the replaced one, deleted by it, stays out of Recents, and Redo follows
    /// the incoming item again.
    @Test func followsAMoveWithReplaceUndoneAndRedone() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/todo.txt", text: "incoming")
        try setup.root.file("b/todo.txt", text: "in the way")
        await setup.operations.recordOpen(FilePath("b/todo.txt"))
        await setup.operations.recordOpen(FilePath("a/todo.txt"))
        try await setup.operations.copy([FilePath("a/todo.txt")])
        _ = try await setup.operations.move(
            into: FilePath("b"), choices: [FilePath("a/todo.txt"): .replace])
        #expect(setup.recents.paths() == [FilePath("b/todo.txt")])

        _ = try await setup.operations.undo()
        #expect(try setup.text("b/todo.txt") == "in the way")
        #expect(setup.recents.paths() == [FilePath("a/todo.txt")])

        _ = try await setup.operations.redo()
        #expect(try setup.text("b/todo.txt") == "incoming")
        #expect(setup.recents.paths() == [FilePath("b/todo.txt")])
    }

    /// Paste leaves the originals where they were.
    @Test func ignoresAPaste() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        try setup.root.folder("archive")
        await setup.operations.recordOpen(FilePath("notes/todo.txt"))
        try await setup.operations.copy([FilePath("notes")])
        _ = try await setup.operations.paste(into: FilePath("archive"), choices: [:])
        #expect(setup.recents.paths() == [FilePath("notes/todo.txt")])
    }

    /// A deleted item leaves Recents for good: neither restoring it nor a
    /// namesake made later brings it back.
    @Test func dropsADeletedItem() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        try setup.root.file("other.txt")
        await setup.operations.recordOpen(FilePath("other.txt"))
        await setup.operations.recordOpen(FilePath("notes/todo.txt"))
        _ = try await setup.operations.delete([FilePath("notes")])
        #expect(setup.recents.paths() == [FilePath("other.txt")])

        _ = try await setup.operations.undo()
        #expect(setup.exists("notes/todo.txt"))
        #expect(setup.recents.paths() == [FilePath("other.txt")])
    }

    /// Replace sends the item in the way to the bin; the incoming one, when
    /// moved, follows.
    @Test func dropsAReplacedItem() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a/todo.txt", text: "incoming")
        try setup.root.file("b/todo.txt", text: "in the way")
        await setup.operations.recordOpen(FilePath("b/todo.txt"))
        await setup.operations.recordOpen(FilePath("a/todo.txt"))
        try await setup.operations.copy([FilePath("a/todo.txt")])
        _ = try await setup.operations.move(
            into: FilePath("b"), choices: [FilePath("a/todo.txt"): .replace])
        #expect(setup.recents.paths() == [FilePath("b/todo.txt")])
        #expect(try setup.text("b/todo.txt") == "incoming")
    }

    /// An item gone outside Files is dropped before Files makes another with
    /// its path, which isn't the one opened.
    @Test func dropsMissingItemsBeforeMakingOne() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("x.txt")
        await setup.operations.recordOpen(FilePath("x.txt"))
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "x.txt"))
        _ = try await setup.operations.createFile(named: "x.txt", in: .root)
        #expect(setup.recents.paths().isEmpty)
    }

    // MARK: Settings

    @Test func showLastDefaultsToFive() throws {
        let defaults = try #require(UserDefaults(suiteName: "RecentsTests-\(UUID())"))
        #expect(RecentsSettings.showLast(in: defaults) == 5)
        defaults.set(10, forKey: RecentsSettings.showLastKey)
        #expect(RecentsSettings.showLast(in: defaults) == 10)
        #expect(RecentsSettings.showLastChoices == [3, 5, 10, 20])
    }
}
