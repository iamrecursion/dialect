import Foundation
import Testing

@testable import Dialect

/// The clipboard: what it holds, kept in Files' stores, and following what
/// Files does to the items.
struct ClipboardTests {
    // MARK: The store

    @Test func keepsPathsInItsFile() throws {
        let setup = try OperationsSetup()
        let paths = [FilePath("notes/todo.txt"), FilePath("scripts")]
        try setup.clipboard.write(paths)
        #expect(setup.clipboard.paths() == paths)

        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: FilesStores.clipboard(in: setup.stores.url)))
        let record = try #require(json as? [String: Any])
        #expect(record["format"] as? Int == 1)
        #expect(record["items"] as? [[String]] == [["notes", "todo.txt"], ["scripts"]])
    }

    @Test func isEmptyWithoutAReadableFile() throws {
        let setup = try OperationsSetup()
        #expect(setup.clipboard.paths().isEmpty)
        try Data("not json".utf8).write(to: FilesStores.clipboard(in: setup.stores.url))
        #expect(setup.clipboard.paths().isEmpty)
    }

    /// Reading leaves out what's gone without writing, as screens read it off
    /// the actor.
    @Test func readsOnlyWhatIsThere() throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        try setup.root.folder("scripts")
        let held = [FilePath("notes/todo.txt"), FilePath("gone.txt"), FilePath("scripts")]
        try setup.clipboard.write(held)

        let items = setup.clipboard.items(root: setup.root.url, textExtensions: [])
        #expect(items.map(\.path) == [FilePath("notes/todo.txt"), FilePath("scripts")])
        #expect(items.map(\.kind) == [.text, .folder])
        #expect(setup.clipboard.paths() == held)
    }

    // MARK: Following changes

    @Test func followsAnItemAndWhatIsInside() {
        let held = [FilePath("notes"), FilePath("notes/todo.txt"), FilePath("notes2/a.md")]
        #expect(
            held.following(FilePath("notes"), to: FilePath("archive/notes")) == [
                FilePath("archive/notes"), FilePath("archive/notes/todo.txt"),
                FilePath("notes2/a.md"),
            ])
    }

    @Test func dropsAnItemAndWhatIsInside() {
        let held = [FilePath("notes"), FilePath("notes/todo.txt"), FilePath("notes2/a.md")]
        #expect(held.dropping(within: FilePath("notes")) == [FilePath("notes2/a.md")])
    }

    // MARK: Through Files' operations

    @Test func copyReplacesWhatWasHeld() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("b.txt")
        try setup.root.file("c.txt")
        try await setup.operations.copy([FilePath("a.txt")])
        #expect(setup.clipboard.paths() == [FilePath("a.txt")])
        try await setup.operations.copy([FilePath("b.txt"), FilePath("c.txt")])
        #expect(setup.clipboard.paths() == [FilePath("b.txt"), FilePath("c.txt")])
        try await setup.operations.clearClipboard()
        #expect(setup.clipboard.paths().isEmpty)
    }

    /// The clipboard is in the stores, so another launch finds it.
    @Test func persists() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try await setup.operations.copy([FilePath("a.txt")])
        let relaunched = FileOperations(root: setup.root.url, stores: setup.stores.url)
        #expect(relaunched.clipboard.paths() == [FilePath("a.txt")])
    }

    @Test func followsARename() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        try await setup.operations.copy([FilePath("notes/todo.txt")])
        _ = try await setup.operations.rename(FilePath("notes"), to: "Notes")
        #expect(setup.clipboard.paths() == [FilePath("Notes/todo.txt")])
        _ = try await setup.operations.rename(FilePath("Notes/todo.txt"), to: "tasks.txt")
        #expect(setup.clipboard.paths() == [FilePath("Notes/tasks.txt")])
    }

    /// A deleted item leaves the clipboard, so a namesake made later isn't
    /// taken for it, and restoring it doesn't bring it back.
    @Test func dropsADeletedItem() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("notes/todo.txt")
        try setup.root.file("other.txt")
        try await setup.operations.copy([FilePath("notes/todo.txt")])
        let deleted = try await setup.operations.delete([FilePath("notes")])
        #expect(setup.clipboard.paths().isEmpty)

        try setup.root.file("notes/todo.txt")
        #expect(setup.clipboard.items(root: setup.root.url, textExtensions: []).isEmpty)
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "notes"))
        _ = try await setup.operations.restore(try #require(deleted.first))
        #expect(setup.clipboard.paths().isEmpty)
    }

    /// What went missing outside Files leaves the store when Files next changes
    /// it.
    @Test func dropsMissingItemsWhenItNextWrites() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt")
        try setup.root.file("b.txt")
        try await setup.operations.copy([FilePath("a.txt"), FilePath("b.txt")])
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "a.txt"))
        _ = try await setup.operations.rename(FilePath("b.txt"), to: "c.txt")
        #expect(setup.clipboard.paths() == [FilePath("c.txt")])
    }

    /// A held item gone outside Files is dropped before Files makes another
    /// with its path, which isn't the one copied.
    @Test func dropsMissingItemsBeforeMakingOne() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("x.txt")
        try await setup.operations.copy([FilePath("x.txt")])
        try FileManager.default.removeItem(at: setup.root.url.appending(path: "x.txt"))
        _ = try await setup.operations.createFile(named: "x.txt", in: .root)
        #expect(setup.clipboard.paths().isEmpty)
    }

    /// A link is held as the link, even when it's broken.
    @Test func holdsALink() async throws {
        let setup = try OperationsSetup()
        try FileManager.default.createSymbolicLink(
            atPath: setup.root.url.appending(path: "broken").path(percentEncoded: false),
            withDestinationPath: "nowhere")
        try await setup.operations.copy([FilePath("broken")])
        #expect(
            setup.clipboard.items(root: setup.root.url, textExtensions: []).map(\.path) == [
                FilePath("broken")
            ])
    }
}
