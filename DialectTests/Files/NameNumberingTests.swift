import Foundation
import Testing

@testable import Dialect

/// Free names for an item whose name is taken: " 2", " 3" as the Finder numbers
/// them, and a restore's deletion date.
struct NameNumberingTests {
    private func next(_ name: String, directory: Bool = false, taken: [String]) -> String {
        return NameNumbering.nextFree(for: name, isDirectory: directory, taken: taken)
    }

    /// A number or date that would take a name past APFS's 255 bytes shortens
    /// the base and keeps the extension.
    @Test func shortensANameToFit() {
        let long = String(repeating: "é", count: 125) + ".md"  // 250 + 3 = 253 bytes
        let numbered = next(long, taken: [long])
        #expect(numbered.utf8.count <= 255)
        #expect(numbered.hasSuffix(" 2.md"))
        let dated = NameNumbering.dated(
            long, isDirectory: false, deleted: Date(timeIntervalSince1970: 1_791_201_600))
        #expect(dated.utf8.count <= 255)
        #expect(dated.hasSuffix("-2026-10-05.md"))
        // Characters are dropped whole, never part of one.
        #expect(
            dated.unicodeScalars.allSatisfy {
                $0 == "é" || "-.0123456789md".unicodeScalars.contains($0)
            })
    }

    @Test func keepsAFreeName() {
        #expect(next("notes.md", taken: ["todo.txt"]) == "notes.md")
    }

    @Test func numbersBeforeTheExtension() {
        #expect(next("notes.md", taken: ["notes.md"]) == "notes 2.md")
        #expect(next("notes.md", taken: ["notes.md", "notes 2.md"]) == "notes 3.md")
    }

    @Test func numbersFromTheLowestFreeNumber() {
        #expect(next("notes.md", taken: ["notes.md", "notes 3.md"]) == "notes 2.md")
    }

    @Test func numbersFoldersWhole() {
        #expect(next("v1.old", directory: true, taken: ["v1.old"]) == "v1.old 2")
        #expect(next("old", directory: true, taken: ["old"]) == "old 2")
    }

    @Test func numbersSessionsBeforeDial() {
        #expect(next("demo.dial", directory: true, taken: ["demo.dial"]) == "demo 2.dial")
    }

    @Test func numbersNamesWithoutAnExtension() {
        #expect(next("readme", taken: ["readme"]) == "readme 2")
        #expect(next(".config", taken: [".config"]) == ".config 2")
    }

    @Test func doesNotNumberANumberedName() {
        #expect(next("draft 2.scm", taken: ["draft.scm", "draft 2.scm"]) == "draft 3.scm")
        // Not a number: part of the name.
        #expect(next("v 1a.txt", taken: ["v 1a.txt"]) == "v 1a 2.txt")
    }

    @Test func comparesAsTheFilesystemDoes() {
        #expect(next("notes.md", taken: ["Notes.md"]) == "notes 2.md")
        #expect(next("Caf\u{E9}", taken: ["Cafe\u{301}"]) == "Caf\u{E9} 2")
    }

    // MARK: Dated names

    private let utc = TimeZone(identifier: "UTC")!
    private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

    /// 2026-10-05 14:05 UTC.
    private let afternoon = Date(timeIntervalSince1970: 1_791_209_100)

    private func dated(_ name: String, directory: Bool = false, timeZone: TimeZone? = nil)
        -> String
    {
        return NameNumbering.dated(
            name, isDirectory: directory, deleted: afternoon, timeZone: timeZone ?? utc)
    }

    @Test func datesBeforeTheExtension() {
        #expect(dated("readme") == "readme-2026-10-05")
        #expect(dated("notes.md") == "notes-2026-10-05.md")
        #expect(dated("demo.dial", directory: true) == "demo-2026-10-05.dial")
        #expect(dated("v1.old", directory: true) == "v1.old-2026-10-05")
        #expect(dated(".config") == ".config-2026-10-05")
    }

    /// The deletion's local date, either side of midnight.
    @Test func usesTheLocalDate() {
        // 23:30 UTC is 01:30 the next day in Amsterdam (CEST, UTC+2).
        let late = Date(timeIntervalSince1970: 1_791_243_000)
        #expect(
            NameNumbering.dated("a.md", isDirectory: false, deleted: late, timeZone: utc)
                == "a-2026-10-05.md")
        #expect(
            NameNumbering.dated("a.md", isDirectory: false, deleted: late, timeZone: amsterdam)
                == "a-2026-10-06.md")
    }

    @Test func numbersADatedNameThatsTaken() {
        let name = dated("notes.md")
        #expect(next(name, taken: [name]) == "notes-2026-10-05 2.md")
    }
}
