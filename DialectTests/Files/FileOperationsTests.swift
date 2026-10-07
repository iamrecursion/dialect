import Foundation
import Testing

@testable import Dialect

/// Making and renaming items: staged, renamed into place, and checked against
/// the folder's current contents.
struct FileOperationsTests {
    // MARK: Making

    @Test func makesAFolder() async throws {
        let setup = try OperationsSetup()
        try setup.root.folder("scripts")
        let made = try await setup.operations.createFolder(named: "lib", in: FilePath("scripts"))
        #expect(made == FilePath("scripts/lib"))
        var isDirectory: ObjCBool = false
        #expect(
            FileManager.default.fileExists(
                atPath: setup.root.url.appending(path: "scripts/lib").path(percentEncoded: false),
                isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(setup.staged().isEmpty)
    }

    /// A session is a manifest and an empty source, placed together.
    @Test func makesASession() async throws {
        let setup = try OperationsSetup()
        let made = try await setup.operations.createSession(named: "scratch.dial", in: .root)
        #expect(made == FilePath("scratch.dial"))
        #expect(try setup.names("scratch.dial") == ["main.scm", "manifest.json"])
        let manifest = try JSONSerialization.jsonObject(
            with: Data(try setup.text("scratch.dial/manifest.json").utf8))
        #expect((manifest as? [String: Int]) == ["format": 1])
        #expect(try setup.text("scratch.dial/main.scm") == "")
        #expect(setup.staged().isEmpty)
    }

    @Test func makesAnEmptyFile() async throws {
        let setup = try OperationsSetup()
        let made = try await setup.operations.createFile(named: "hello.scm", in: .root)
        #expect(made == FilePath("hello.scm"))
        #expect(try setup.text("hello.scm") == "")
        #expect(setup.staged().isEmpty)
    }

    /// A name taken after the name screen checked it, by the REPL say, is
    /// refused.
    @Test func refusesANameTakenSinceItWasChecked() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("Notes.md", text: "keep me")
        await #expect(throws: FileOperationError.name(.taken("notes.md"))) {
            try await setup.operations.createFile(named: "notes.md", in: .root)
        }
        await #expect(throws: FileOperationError.name(.taken("notes.md"))) {
            try await setup.operations.createFolder(named: "notes.md", in: .root)
        }
        #expect(try setup.names() == ["Notes.md"])
        #expect(try setup.text("Notes.md") == "keep me")
        #expect(setup.staged().isEmpty)
    }

    @Test func refusesANameTheRulesRefuse() async throws {
        let setup = try OperationsSetup()
        await #expect(throws: FileOperationError.name(.folderEndsInDial)) {
            try await setup.operations.createFolder(named: "x.dial", in: .root)
        }
        await #expect(throws: FileOperationError.name(.slash)) {
            try await setup.operations.createFile(named: "a/b", in: .root)
        }
        #expect(try setup.names().isEmpty)
    }

    /// A name taken while the item is being made: the rename into place fails,
    /// and the existing item stays.
    @Test func refusesANameTakenWhileMaking() async throws {
        let setup = try OperationsSetup()
        let root = setup.root
        await #expect(throws: FileOperationError.name(.taken("lib"))) {
            try await setup.operations.create("lib", kind: .folder, in: .root) { url in
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                try root.file("lib/keep.txt", text: "keep me")
            }
        }
        #expect(try setup.names("lib") == ["keep.txt"])
        #expect(setup.staged().isEmpty)
    }

    @Test func failsWhenTheFolderGoesWhileMaking() async throws {
        let setup = try OperationsSetup()
        let scripts = try setup.root.folder("scripts")
        await #expect(throws: FileOperationError.gone("scripts")) {
            try await setup.operations.create("a.scm", kind: .file, in: FilePath("scripts")) {
                url in
                try Data().write(to: url)
                try FileManager.default.removeItem(at: scripts)
            }
        }
        #expect(setup.staged().isEmpty)
    }

    @Test func failsWhenTheFolderIsGone() async throws {
        let setup = try OperationsSetup()
        await #expect(throws: FileOperationError.gone("scripts")) {
            try await setup.operations.createFile(named: "a.scm", in: FilePath("scripts"))
        }
    }

    /// Nothing reaches the folder when making fails part way.
    @Test func leavesNothingWhenMakingFails() async throws {
        let setup = try OperationsSetup()
        let staging = FilesStores.staging(in: setup.stores.url)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let stagingPath = staging.path(percentEncoded: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: stagingPath)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: stagingPath)
        }
        await #expect(throws: (any Error).self) {
            try await setup.operations.createSession(named: "scratch.dial", in: .root)
        }
        await #expect(throws: (any Error).self) {
            try await setup.operations.createFile(named: "a.scm", in: .root)
        }
        #expect(try setup.names().isEmpty)
    }

    @Test func clearsLeftoversFromStaging() async throws {
        let setup = try OperationsSetup()
        let staging = FilesStores.staging(in: setup.stores.url)
        try FileManager.default.createDirectory(
            at: staging.appending(path: UUID().uuidString), withIntermediateDirectories: true)
        try Data().write(to: staging.appending(path: UUID().uuidString))
        await setup.operations.clearStaging()
        #expect(setup.staged().isEmpty)
    }

    // MARK: Renaming

    @Test func renamesAFile() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("scripts/prelude.scm", text: "p")
        let renamed = try await setup.operations.rename(
            FilePath("scripts/prelude.scm"), to: "base.scm")
        #expect(renamed == FilePath("scripts/base.scm"))
        #expect(try setup.names("scripts") == ["base.scm"])
        #expect(try setup.text("scripts/base.scm") == "p")
    }

    @Test func renamesOnlyTheCase() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("Notes.md")
        try setup.root.file("todo.txt")
        let renamed = try await setup.operations.rename(FilePath("Notes.md"), to: "notes.md")
        #expect(renamed == FilePath("notes.md"))
        #expect(try setup.names() == ["notes.md", "todo.txt"])
    }

    /// Foundation writes names decomposed, but C library calls can write
    /// composed ones, which still take the name.
    @Test func refusesANameTakenInTheOtherForm() async throws {
        let setup = try OperationsSetup()
        let composed = setup.root.url.path(percentEncoded: false) + "/Caf\u{E9}.md"
        let descriptor = open(composed, O_CREAT | O_WRONLY, 0o644)
        try #require(descriptor >= 0)
        close(descriptor)
        try #require(
            setup.names().map { Array($0.unicodeScalars) } == [Array("Caf\u{E9}.md".unicodeScalars)]
        )
        await #expect(throws: FileOperationError.name(.taken("Cafe\u{301}.md"))) {
            try await setup.operations.createFile(named: "Cafe\u{301}.md", in: .root)
        }
        #expect(try setup.names().count == 1)
    }

    /// A folder's view settings are stored on the folder, so a rename keeps
    /// them.
    @Test func keepsAFoldersViewSettings() async throws {
        let setup = try OperationsSetup()
        let folder = try setup.root.folder("v1")
        var settings = FolderViewSettings()
        settings.sort = .size
        settings.grouping = .kind
        try settings.write(to: folder)
        _ = try await setup.operations.rename(FilePath("v1"), to: "v2")
        #expect(FolderViewSettings.read(at: setup.root.url.appending(path: "v2")) == settings)
    }

    @Test func refusesATakenNameWhenRenaming() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt", text: "a")
        try setup.root.file("b.txt", text: "b")
        await #expect(throws: FileOperationError.name(.taken("B.txt"))) {
            try await setup.operations.rename(FilePath("a.txt"), to: "B.txt")
        }
        #expect(try setup.text("a.txt") == "a")
        #expect(try setup.text("b.txt") == "b")
    }

    @Test func refusesASessionsNameForAFolder() async throws {
        let setup = try OperationsSetup()
        try setup.root.folder("lib")
        await #expect(throws: FileOperationError.name(.folderEndsInDial)) {
            try await setup.operations.rename(FilePath("lib"), to: "lib.dial")
        }
    }

    /// A link is checked as its target, as the listing shows it.
    @Test func checksALinkAsWhatItLeadsTo() async throws {
        let setup = try OperationsSetup()
        let folder = try setup.root.folder("real")
        try FileManager.default.createSymbolicLink(
            at: setup.root.url.appending(path: "link"), withDestinationURL: folder)
        await #expect(throws: FileOperationError.name(.folderEndsInDial)) {
            try await setup.operations.rename(FilePath("link"), to: "link.dial")
        }
        // A broken link is still there to rename.
        try FileManager.default.createSymbolicLink(
            at: setup.root.url.appending(path: "broken"),
            withDestinationURL: setup.root.url.appending(path: "nowhere"))
        #expect(
            try await setup.operations.rename(FilePath("broken"), to: "b.dial")
                == FilePath("b.dial"))
    }

    @Test func failsToRenameWhatsGone() async throws {
        let setup = try OperationsSetup()
        await #expect(throws: FileOperationError.gone("draft.scm")) {
            try await setup.operations.rename(FilePath("draft.scm"), to: "final.scm")
        }
    }

    /// Renaming to the same name does nothing.
    @Test func renamingToTheSameNameDoesNothing() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("a.txt", text: "a")
        #expect(
            try await setup.operations.rename(FilePath("a.txt"), to: "a.txt") == FilePath("a.txt"))
        #expect(try setup.names() == ["a.txt"])
    }

    // MARK: Folder sizes

    /// Cached totals above a change are recomputed, as a folder's date doesn't
    /// change when something deeper does.
    @Test func forgetsTheTotalsAboveAChange() async throws {
        let setup = try OperationsSetup()
        try setup.root.file("tree/sub/a.txt", Data(count: 10))
        let tree = setup.root.url.appending(path: "tree")
        #expect(await setup.sizes.size(of: tree, modified: nil) == 10)
        try setup.root.file("tree/sub/b.txt", Data(count: 5))
        _ = try await setup.operations.rename(FilePath("tree/sub/b.txt"), to: "c.txt")
        #expect(await setup.sizes.size(of: tree, modified: nil) == 15)
    }

    @Test func errorsSayWhy() {
        #expect(
            FileOperationError.name(.taken("notes.md")).localizedDescription
                == NameProblem.taken("notes.md").reason)
        #expect(FileOperationError.gone("scripts").localizedDescription.contains("scripts"))
        #expect(
            FileOperationError.intoItself("scripts").localizedDescription
                == "scripts can't be moved into itself.")
        #expect(
            FileOperationError.intoOwnFolder("scripts").localizedDescription
                == "scripts can't be moved into a folder inside it.")
    }
}
