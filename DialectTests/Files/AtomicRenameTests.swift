import Foundation
import Testing

@testable import Dialect

/// Renaming in one step that never replaces what's already there.
struct AtomicRenameTests {
    private func names(in folder: URL) throws -> [String] {
        return try FileManager.default.contentsOfDirectory(
            atPath: folder.path(percentEncoded: false)
        )
        .sorted()
    }

    @Test func renamesToAFreeName() throws {
        let root = try TemporaryRoot()
        let from = try root.file("a.txt", text: "a")
        try AtomicRename.rename(from, to: root.url.appending(path: "b.txt"))
        #expect(try names(in: root.url) == ["b.txt"])
        #expect(try String(contentsOf: root.url.appending(path: "b.txt"), encoding: .utf8) == "a")
    }

    /// A rename onto a name taken after the check fails, and both items stay as
    /// they were.
    @Test func neverReplacesATakenName() throws {
        let root = try TemporaryRoot()
        let from = try root.file("a.txt", text: "a")
        let to = try root.file("b.txt", text: "b")
        #expect {
            try AtomicRename.rename(from, to: to)
        } throws: { error in
            (error as? CocoaError)?.code == .fileWriteFileExists
        }
        #expect(try String(contentsOf: from, encoding: .utf8) == "a")
        #expect(try String(contentsOf: to, encoding: .utf8) == "b")
    }

    /// A name taken in another case counts as taken.
    @Test func neverReplacesANameTakenInAnotherCase() throws {
        let root = try TemporaryRoot()
        let from = try root.file("a.txt", text: "a")
        try root.file("B.txt", text: "b")
        #expect(throws: CocoaError.self) {
            try AtomicRename.rename(from, to: root.url.appending(path: "b.txt"))
        }
        #expect(try names(in: root.url) == ["B.txt", "a.txt"])
    }

    @Test func renamesOnlyTheCase() throws {
        let root = try TemporaryRoot()
        let from = try root.file("Notes.md", text: "n")
        try AtomicRename.rename(from, to: root.url.appending(path: "notes.md"))
        #expect(try names(in: root.url) == ["notes.md"])
    }

    @Test func failsWhenTheItemIsGone() throws {
        let root = try TemporaryRoot()
        #expect {
            try AtomicRename.rename(
                root.url.appending(path: "gone.txt"), to: root.url.appending(path: "b.txt"))
        } throws: { error in
            (error as? CocoaError)?.code == .fileNoSuchFile
        }
    }
}
