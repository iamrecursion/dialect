import Foundation
import Testing

@testable import Dialect

/// Kinds by name, and the text-like check for everything else.
struct FileKindTests {
    private func kind(_ name: String, directory: Bool = false, text: Set<String> = [])
        -> FileKind?
    {
        return FileKind.classify(name: name, isDirectory: directory, textExtensions: text)
    }

    @Test(arguments: [
        ("prelude.scm", FileKind.scheme), ("util.sld", .scheme),
        ("notes.md", .text), ("todo.txt", .text), ("config.toml", .text),
        ("settings.yaml", .text), ("data.json", .text), ("feed.xml", .text), ("table.csv", .text),
        ("a.jpg", .image), ("a.jpeg", .image), ("a.png", .image), ("a.gif", .image),
        ("a.heic", .image), ("a.heif", .image), ("a.tif", .image), ("a.tiff", .image),
        ("a.jxl", .image),
        ("a.mp4", .video), ("a.mov", .video), ("a.m4v", .video),
    ])
    func classifiesEveryExtensionInTheTable(name: String, expected: FileKind) {
        #expect(kind(name) == expected)
        #expect(kind(name.uppercased()) == expected, "\(name.uppercased())")
    }

    @Test func classifiesDirectories() {
        #expect(kind("scripts", directory: true) == .folder)
        #expect(kind("notes.md", directory: true) == .folder)
        #expect(kind("demo.dial", directory: true) == .session)
        #expect(kind("Demo.DIAL", directory: true) == .session)
    }

    /// A `.dial` file is sniffed like any unknown file.
    @Test func leavesUnknownFilesToTheTextCheck() {
        #expect(kind("demo.dial") == nil)
        #expect(kind("readme") == nil)
        #expect(kind("blob.bin") == nil)
        #expect(kind(".hidden-config") == nil)
    }

    @Test func addsTheUsersTextExtensions() {
        #expect(kind("init.el", text: ["el", "rkt"]) == .text)
        #expect(kind("INIT.EL", text: ["el"]) == .text)
        #expect(kind("init.el") == nil)
    }

    @Test func sniffsText() throws {
        let root = try TemporaryRoot()
        #expect(FileKind.sniff(try root.file("readme", text: "Hello, λ!\n")) == .otherText)
        #expect(FileKind.sniff(try root.file("empty")) == .otherText)
    }

    @Test func sniffsBinary() throws {
        let root = try TemporaryRoot()
        #expect(FileKind.sniff(try root.file("nul", Data([0x41, 0x00, 0x42]))) == .binary)
        #expect(FileKind.sniff(try root.file("latin1", Data([0x43, 0x61, 0x66, 0xE9]))) == .binary)
        #expect(FileKind.sniff(try root.file("bytes", Data(0...255))) == .binary)
        #expect(FileKind.sniff(root.url.appending(path: "missing")) == .binary)
    }

    /// A multi-byte character cut by the 4096-byte limit is still text: only
    /// the first 4096 bytes are read.
    @Test func forgivesACharacterCutAtTheLimit() throws {
        let root = try TemporaryRoot()
        for prefix in 4093...4095 {
            let text = String(repeating: "a", count: prefix) + "🙂🙂"
            #expect(
                FileKind.sniff(try root.file("cut\(prefix)", text: text)) == .otherText,
                "\(prefix)")
        }
    }

    /// Only a cut at the limit is forgiven: a short file ending mid-character
    /// is broken.
    @Test func refusesAnIncompleteCharacterBeforeTheLimit() throws {
        let root = try TemporaryRoot()
        let broken = Data("abc".utf8) + Data([0xF0, 0x9F, 0x99])
        #expect(FileKind.sniff(try root.file("broken", broken)) == .binary)
    }

    @Test func groupsAndTypeNames() {
        let expected: [(FileKind, KindGroup, String)] = [
            (.folder, .folders, "Folder"), (.session, .sessions, "Session"),
            (.scheme, .scheme, "Scheme Source"), (.text, .text, "Text Document"),
            (.image, .images, "Image"), (.video, .videos, "Video"),
            (.otherText, .other, "Document"), (.binary, .other, "Binary File"),
        ]
        for (kind, group, typeName) in expected {
            #expect(kind.group == group)
            #expect(kind.typeName.key == typeName)
        }
        #expect(
            KindGroup.allCases.map(\.title.key) == [
                "Folders", "Sessions", "Scheme", "Text", "Images", "Videos", "Other",
            ])
    }
}
