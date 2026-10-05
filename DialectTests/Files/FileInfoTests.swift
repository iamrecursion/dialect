import Foundation
import Testing

@testable import Dialect

/// Info's fields, and the Extended screen's permissions and attributes.
struct FileInfoTests {
    private let created = Date(timeIntervalSince1970: 1_000)
    private let modified = Date(timeIntervalSince1970: 2_000)

    private func item(_ components: [String], _ kind: FileKind, size: Int64? = nil) -> FileItem {
        return FileItem(
            path: FilePath(components: components), kind: kind,
            isDirectory: kind == .folder || kind == .session, size: size, created: created,
            modified: modified, isReadOnly: false)
    }

    private func fields(
        _ item: FileItem, size: Int64? = nil, itemCount: Int? = nil
    ) -> [(InfoField.Label, String)] {
        return FileInfo.fields(
            for: item, size: size ?? item.size, itemCount: itemCount,
            date: { $0 == self.created ? "then" : "later" }
        ).map { ($0.label, $0.value) }
    }

    @Test func aFilesFields() {
        let notes = item(["notes", "notes.md"], .text, size: 2048)
        let result = fields(notes)
        #expect(
            result.map(\.0) == [
                .name, .ext, .type, .size, .created, .modified, .path, .hidden, .readOnly,
            ])
        #expect(
            result.map(\.1) == [
                "notes", "md", "Text Document", "2 KB", "then", "later", "/notes/notes.md", "No",
                "No",
            ])
    }

    @Test func aFileWithoutAnExtension() {
        let result = Dictionary(uniqueKeysWithValues: fields(item(["readme"], .otherText, size: 1)))
        #expect(result[.name] == "readme")
        #expect(result[.ext] == "None")
        #expect(result[.type] == "Document")
    }

    /// Folders have no Extension; Folder Info adds Items.
    @Test func aFoldersFields() {
        let result = fields(item(["scripts"], .folder), size: 4096, itemCount: 3)
        #expect(
            result.map(\.0) == [
                .name, .type, .size, .created, .modified, .path, .hidden, .readOnly, .items,
            ])
        #expect(Dictionary(uniqueKeysWithValues: result)[.items] == "3")
        #expect(Dictionary(uniqueKeysWithValues: result)[.size] == "4 KB")
    }

    @Test func aSessionShowsItsExtension() {
        let result = Dictionary(uniqueKeysWithValues: fields(item(["demo.dial"], .session)))
        #expect(result[.name] == "demo")
        #expect(result[.ext] == "dial")
        #expect(result[.type] == "Session")
        #expect(result[.size] == "—")
    }

    @Test func theRoot() {
        let result = Dictionary(uniqueKeysWithValues: fields(item([], .folder), itemCount: 9))
        #expect(result[.name] == "Files")
        #expect(result[.path] == "/")
        #expect(result[.ext] == nil)
    }

    @Test func hiddenAndReadOnly() {
        let config = FileItem(
            path: FilePath(components: [".hidden-config"]), kind: .otherText, isDirectory: false,
            size: 1, created: nil, modified: nil, isReadOnly: true)
        let result = Dictionary(uniqueKeysWithValues: fields(config))
        #expect(result[.hidden] == "Yes")
        #expect(result[.readOnly] == "Yes")
        #expect(result[.created] == "—")
    }

    /// The header's line under the name.
    @Test func summary() {
        #expect(FileInfo.summary(for: item(["a.md"], .text), size: 2048) == "Text Document · 2 KB")
        #expect(FileInfo.summary(for: item(["s"], .folder), size: nil) == "Folder · —")
    }

    /// The card leaves out what the header already shows.
    @Test func cardFields() {
        let all = FileInfo.fields(
            for: item(["notes.md"], .text, size: 1), size: 1, itemCount: nil, date: { _ in "" })
        #expect(
            FileInfo.cardFields(all).map(\.label) == [
                .ext, .created, .modified, .path, .hidden, .readOnly,
            ])
    }

    @Test func labels() {
        #expect(
            InfoField.Label.allCases.map(\.title.key) == [
                "Name", "Extension", "Type", "Size", "Created", "Modified", "Path", "Hidden",
                "Read Only", "Items",
            ])
    }

    // MARK: Extended

    @Test func permissionsAsText() {
        #expect(FileInfo.permissions(0o644) == "rw-r--r--")
        #expect(FileInfo.permissions(0o755) == "rwxr-xr-x")
        #expect(FileInfo.permissions(0o000) == "---------")
        #expect(FileInfo.permissions(0o100644) == "rw-r--r--")
    }

    @Test func whatThePermissionsMean() {
        #expect(FileInfo.access(0o644) == ["Owner: Read, Write", "Group: Read", "Everyone: Read"])
        #expect(
            FileInfo.access(0o750) == [
                "Owner: Read, Write, Execute", "Group: Read, Execute", "Everyone: No Access",
            ])
    }

    @Test func readsExtendedInfo() throws {
        let root = try TemporaryRoot()
        let folder = try root.folder("notes")
        try FolderViewSettings(sort: .size).write(to: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)

        let info = try #require(FileInfo.extended(at: folder))
        #expect(info.permissions == "rwxr-xr-x")
        #expect(!info.owner.isEmpty)
        #expect(!info.group.isEmpty)
        #expect(info.attributes.map(\.name).contains(FolderViewSettings.attributeName))
        #expect(FileInfo.extended(at: root.url.appending(path: "gone")) == nil)
    }

    /// Info appears at once; a folder's total follows in a second step.
    @Test func loadsAFoldersTotalSecond() async throws {
        let root = try TemporaryRoot()
        try root.file("tree/a.txt", Data(count: 10))
        try root.file("tree/sub/b.txt", Data(count: 5))
        let first = try #require(
            await LoadedInfo.load(FilePath(components: ["tree"]), root: root.url, countsItems: true)
        )
        #expect(first.size == nil)
        #expect(first.itemCount == 2)
        let second = await first.withTotal(root: root.url)
        #expect(second.size == 15)
        #expect(second.itemCount == 2)

        let file = try #require(
            await LoadedInfo.load(
                FilePath(components: ["tree", "a.txt"]), root: root.url, countsItems: false))
        #expect(file.size == 10)
        let gone = await LoadedInfo.load(
            FilePath(components: ["gone"]), root: root.url, countsItems: false)
        #expect(gone == nil)
    }

    /// Folder Info's Items counts hidden entries too, whatever Show Hidden
    /// says.
    @Test func countsEveryItem() throws {
        let root = try TemporaryRoot()
        try root.file("a/one.txt")
        try root.file("a/.hidden")
        try root.folder("a/sub")
        #expect(FileInfo.itemCount(at: root.url.appending(path: "a")) == 3)
        #expect(FileInfo.itemCount(at: root.url.appending(path: "gone")) == nil)
    }
}
