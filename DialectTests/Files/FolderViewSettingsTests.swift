import Foundation
import Testing

@testable import Dialect

/// A folder's sort and grouping, kept in an extended attribute on the folder.
struct FolderViewSettingsTests {
    private let attribute = FolderViewSettings.attributeName

    @Test func defaults() {
        let settings = FolderViewSettings()
        #expect(settings.sort == .name)
        #expect(settings.ascending)
        #expect(settings.grouping == .none)
        #expect(attribute == "com.iamrecursion.dialect.view")
    }

    @Test func roundTrips() throws {
        let root = try TemporaryRoot()
        let folder = try root.folder("notes")
        let settings = FolderViewSettings(sort: .modified, ascending: false, grouping: .kind)
        try settings.write(to: folder)
        #expect(FolderViewSettings.read(at: folder) == settings)
    }

    @Test func missingOrUnreadableGivesTheDefaults() throws {
        let root = try TemporaryRoot()
        let folder = try root.folder("notes")
        #expect(FolderViewSettings.read(at: folder) == FolderViewSettings())

        try ExtendedAttributes.set(attribute, Data("not json".utf8), at: folder)
        #expect(FolderViewSettings.read(at: folder) == FolderViewSettings())

        #expect(
            FolderViewSettings.read(at: root.url.appending(path: "gone")) == FolderViewSettings())
    }

    /// A newer build may add fields; an older one still reads the rest.
    @Test func toleratesUnknownAndMissingKeys() throws {
        let root = try TemporaryRoot()
        let folder = try root.folder("notes")
        let json = #"{"sort": "size", "future": [1, 2], "grouping": "someday"}"#
        try ExtendedAttributes.set(attribute, Data(json.utf8), at: folder)
        #expect(
            FolderViewSettings.read(at: folder)
                == FolderViewSettings(sort: .size, ascending: true, grouping: .none))
    }

    /// The settings follow a folder that FileManager copies or moves, so
    /// copying needn't carry them.
    @Test func survivesCopyAndMove() throws {
        let root = try TemporaryRoot()
        let folder = try root.folder("notes")
        try root.file("notes/a.md")
        let settings = FolderViewSettings(sort: .size, ascending: false, grouping: .modified)
        try settings.write(to: folder)

        let copy = root.url.appending(path: "copy", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: folder, to: copy)
        #expect(FolderViewSettings.read(at: copy) == settings)

        let moved = root.url.appending(path: "moved", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: folder, to: moved)
        #expect(FolderViewSettings.read(at: moved) == settings)
    }
}

struct ExtendedAttributesTests {
    @Test func setsListsAndRemoves() throws {
        let root = try TemporaryRoot()
        let file = try root.file("a.txt")
        #expect(ExtendedAttributes.get("com.example.test", at: file) == nil)

        try ExtendedAttributes.set("com.example.test", Data("hello".utf8), at: file)
        #expect(ExtendedAttributes.get("com.example.test", at: file) == Data("hello".utf8))
        #expect(
            ExtendedAttributes.names(at: file)
                .contains(ExtendedAttribute(name: "com.example.test", size: 5)))

        try ExtendedAttributes.remove("com.example.test", at: file)
        #expect(ExtendedAttributes.get("com.example.test", at: file) == nil)
        #expect(!ExtendedAttributes.names(at: file).map(\.name).contains("com.example.test"))
    }

    @Test func emptyValue() throws {
        let root = try TemporaryRoot()
        let file = try root.file("a.txt")
        try ExtendedAttributes.set("com.example.empty", Data(), at: file)
        #expect(ExtendedAttributes.get("com.example.empty", at: file) == Data())
    }

    @Test func failsOnAMissingFile() throws {
        let root = try TemporaryRoot()
        let missing = root.url.appending(path: "gone")
        #expect(throws: (any Error).self) {
            try ExtendedAttributes.set("com.example.test", Data(), at: missing)
        }
        #expect(ExtendedAttributes.names(at: missing).isEmpty)
    }
}
