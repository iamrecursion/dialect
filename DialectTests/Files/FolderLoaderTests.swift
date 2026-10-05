import Foundation
import Testing

@testable import Dialect

/// What the folder screen reads when it appears.
struct FolderLoaderTests {
    @Test func readsItemsAndViewSettings() throws {
        let root = try TemporaryRoot()
        let notes = try root.folder("notes")
        try root.file("notes/a.md")
        try root.file("notes/.hidden")
        let settings = FolderViewSettings(sort: .size, ascending: false, grouping: .kind)
        try settings.write(to: notes)

        let contents = FolderLoader.load(
            FilePath(components: ["notes"]), root: root.url, showHidden: false,
            textExtensions: [])
        guard case .items(let items, let read) = contents else {
            Issue.record("\(contents)")
            return
        }
        #expect(items.map(\.name) == ["a.md"])
        #expect(read == settings)
    }

    /// A folder deleted while on the navigation path reads as missing.
    @Test func reportsAFolderThatsGone() throws {
        let root = try TemporaryRoot()
        let gone = try root.folder("gone")
        try FileManager.default.removeItem(at: gone)
        let contents = FolderLoader.load(
            FilePath(components: ["gone"]), root: root.url, showHidden: false, textExtensions: [])
        guard case .missing = contents else {
            Issue.record("\(contents)")
            return
        }
    }

    /// A file where a folder was expected is as good as gone.
    @Test func reportsAFileInTheFoldersPlace() throws {
        let root = try TemporaryRoot()
        try root.file("notes")
        let contents = FolderLoader.load(
            FilePath(components: ["notes"]), root: root.url, showHidden: false, textExtensions: [])
        guard case .missing = contents else {
            Issue.record("\(contents)")
            return
        }
    }

    @Test func rowDetails() {
        let item = FileItem(
            path: FilePath(components: ["a.md"]), kind: .text, isDirectory: false, size: 2048,
            created: nil, modified: Date(timeIntervalSince1970: 1_791_036_300), isReadOnly: false)
        let style = FileRowStyle(
            showExtensions: true, showDetails: true, relativeModified: false, dateStyle: .iso,
            use24Hour: true, now: Date(timeIntervalSince1970: 1_791_036_300),
            timeZone: TimeZone(identifier: "UTC")!)
        #expect(style.detail(for: item, size: item.size) == "2026-10-03 14:05 ∘ 2 KB")
        #expect(style.detail(for: item, size: nil) == "2026-10-03 14:05 ∘ —")

        let undated = FileItem(
            path: FilePath(components: ["x"]), kind: .binary, isDirectory: false, size: nil,
            created: nil, modified: nil, isReadOnly: false)
        #expect(style.detail(for: undated, size: nil) == "— ∘ —")
    }
}
