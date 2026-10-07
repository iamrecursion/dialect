import Foundation
import Testing

@testable import Dialect

/// The bin's directory layout, reading it as items, and each item's days left.
struct BinTests {
    /// 2026-10-05 12:00 UTC: the same day in every time zone within 11 hours.
    static let noon = Date(timeIntervalSince1970: 1_791_201_600)
    private let day: TimeInterval = 24 * 60 * 60

    /// Puts an item and its record in the bin by hand.
    @discardableResult
    private func put(
        _ bin: Bin, _ name: String, from original: String, deleted: Date, record: Bool = true,
        item: Bool = true
    ) throws -> UUID {
        let id = UUID()
        let directory = bin.directory(for: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if record {
            try bin.write(
                Bin.Record(
                    name: name, original: FilePath(original).components, deleted: deleted),
                in: directory)
        }
        if item { try Data("x".utf8).write(to: Bin.item(in: directory)) }
        return id
    }

    @Test func writesTheRecordAsPlanned() throws {
        let stores = try TemporaryRoot()
        let bin = Bin(url: FilesStores.bin(in: stores.url))
        let id = try put(bin, "draft.scm", from: "scripts/draft.scm", deleted: Self.noon)
        let data = try Data(contentsOf: Bin.record(in: bin.directory(for: id)))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["format"] as? Int == 1)
        #expect(json["name"] as? String == "draft.scm")
        #expect(json["original"] as? [String] == ["scripts", "draft.scm"])
        #expect(json["deleted"] as? String == "2026-10-05T12:00:00.000Z")
    }

    /// A date read back and written again stays the same, as when the bin
    /// renames a namesake.
    @Test func keepsADateWrittenAgain() throws {
        let stores = try TemporaryRoot()
        let bin = Bin(url: FilesStores.bin(in: stores.url))
        let deleted = Self.noon + 0.828
        let id = try put(bin, "a", from: "a", deleted: deleted)
        let first = try #require(bin.item(id))
        try bin.write(first.record(named: "a"), in: first.directory)
        #expect(bin.item(id)?.deleted == first.deleted)
        #expect(abs(first.deleted.timeIntervalSince(deleted)) < 0.000_5)
    }

    /// A record written by hand, without fractional seconds, still reads.
    @Test func readsADateWithoutFractionalSeconds() throws {
        let stores = try TemporaryRoot()
        let bin = Bin(url: FilesStores.bin(in: stores.url))
        let id = try put(bin, "a", from: "a", deleted: Self.noon)
        try Data(
            #"{"format":1,"name":"a","original":["a"],"deleted":"2026-10-05T12:00:00Z"}"#.utf8
        ).write(to: Bin.record(in: bin.directory(for: id)))
        #expect(bin.items().map(\.deleted) == [Self.noon])
    }

    @Test func listsTheNewestDeletionFirst() throws {
        let stores = try TemporaryRoot()
        let bin = Bin(url: FilesStores.bin(in: stores.url))
        try put(bin, "old", from: "old", deleted: Self.noon - day)
        try put(bin, "new", from: "a/new", deleted: Self.noon)
        try put(bin, "middle", from: "middle", deleted: Self.noon - 60)
        let items = bin.items()
        #expect(items.map(\.name) == ["new", "middle", "old"])
        #expect(items[0].original == FilePath("a/new"))
        #expect(items[0].isDirectory == false)
    }

    @Test func isEmptyUntilSomethingArrives() throws {
        let stores = try TemporaryRoot()
        let bin = Bin(url: FilesStores.bin(in: stores.url))
        #expect(bin.isEmpty)
        try put(bin, "a", from: "a", deleted: Self.noon)
        #expect(!bin.isEmpty)
    }

    /// A record without its item may be a delete in progress: reading skips it,
    /// and only tidying removes it.
    @Test func leavesARecordWithoutItsItemToTidying() throws {
        let stores = try TemporaryRoot()
        let bin = Bin(url: FilesStores.bin(in: stores.url))
        let id = try put(bin, "a", from: "a", deleted: Self.noon, item: false)
        #expect(bin.items().isEmpty)
        #expect(FileManager.default.fileExists(atPath: bin.directory(for: id).path()))
        bin.tidy()
        #expect(!FileManager.default.fileExists(atPath: bin.directory(for: id).path()))
    }

    /// An item without a record is kept, and restores to the root.
    @Test func keepsAnItemWithoutARecord() throws {
        let stores = try TemporaryRoot()
        let bin = Bin(url: FilesStores.bin(in: stores.url))
        try put(bin, "Recovered Item", from: "x/Recovered Item", deleted: Self.noon)
        let id = try put(bin, "", from: "", deleted: Self.noon, record: false)
        let recovered = try #require(bin.items().first { $0.id == id })
        #expect(recovered.name == "Recovered Item 2")
        #expect(recovered.original == FilePath("Recovered Item 2"))

        bin.tidy()
        #expect(bin.record(in: bin.directory(for: id))?.name == "Recovered Item 2")
        #expect(bin.items().count == 2)
    }

    @Test func findsAnItemByItsID() throws {
        let stores = try TemporaryRoot()
        let bin = Bin(url: FilesStores.bin(in: stores.url))
        let id = try put(bin, "a", from: "a", deleted: Self.noon)
        #expect(bin.item(id)?.name == "a")
        #expect(bin.item(UUID()) == nil)
    }

    // MARK: Restored

    private func restored(_ name: String, from original: String, to path: String) -> Restored {
        let item = BinItem(
            id: UUID(), name: name, original: FilePath(original), deleted: Self.noon,
            isDirectory: false, url: URL(filePath: "/nowhere"))
        return Restored(item: item, path: FilePath(path))
    }

    /// No note for an item back in its folder under its name in the bin,
    /// including after a rename in the bin or with its folder in another case.
    @Test func saysNothingWhenItWentBackWhereItWas() {
        #expect(restored("a.txt", from: "notes/a.txt", to: "notes/a.txt").note == nil)
        #expect(restored("draft 2.scm", from: "s/draft.scm", to: "s/draft 2.scm").note == nil)
        #expect(restored("a.txt", from: "notes/a.txt", to: "Notes/a.txt").note == nil)
    }

    @Test func saysWhenItCameBackDated() {
        #expect(
            restored("readme", from: "readme", to: "readme-2026-10-05").note
                == "It came back as readme-2026-10-05, as something in Files now has its name.")
        #expect(
            restored("f.txt", from: "a/f.txt", to: "a-2026-10-05/f.txt").note
                == "It came back in /a-2026-10-05, as something in Files now has its folder's name."
        )
    }

    @Test func saysHowFarRestoreAllGot() {
        #expect(
            BinMoreScreen.stoppedNote(restored: 2, dated: 0, reason: "Why.")
                == "2 items were restored before Restore All stopped. Why.")
        #expect(
            BinMoreScreen.stoppedNote(restored: 1, dated: 1, reason: "Why.").hasPrefix(
                "1 item was restored before Restore All stopped. 1 item came back with its"))
    }

    // MARK: Days left

    /// "Deleted *when*" (mid-sentence), then the days left on a second line;
    /// no days left when the bin never empties.
    @Test func describesARowsDeletion() {
        let item = item(deleted: Self.noon)
        let lines = BinEntry.detail(
            for: item, now: Self.noon + 3600, relative: false, style: .iso, use24Hour: true,
            emptyAfter: 30)
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Deleted 2026-10-05"))
        #expect(lines[1] == "30 days left")
        #expect(
            BinEntry.detail(
                for: item, now: Self.noon + 29.5 * day, relative: false, style: .iso,
                use24Hour: true, emptyAfter: 30)[1] == "1 day left")
        #expect(
            BinEntry.detail(
                for: item, now: Self.noon, relative: false, style: .iso, use24Hour: true,
                emptyAfter: nil
            ).count == 1)
    }

    @Test func startsARelativeDateMidSentence() {
        let date = DateDisplay.string(
            for: Self.noon - day, now: Self.noon, relative: true, style: .system,
            use24Hour: true, startsSentence: false, locale: Locale(identifier: "en_US"))
        #expect(date == "yesterday")
    }

    private func item(deleted: Date) -> BinItem {
        return BinItem(
            id: UUID(), name: "a", original: FilePath("a"), deleted: deleted, isDirectory: false,
            url: URL(filePath: "/nowhere"))
    }

    @Test func neverExpiresWhenTheBinNeverEmpties() {
        let item = item(deleted: Self.noon)
        let later = Self.noon + 1000 * day
        #expect(!item.isExpired(now: later, after: nil))
        #expect(item.daysLeft(now: later, after: nil) == nil)
    }

    @Test(arguments: [1, 3, 7, 14, 30, 90])
    func expiresAtItsBoundary(_ days: Int) {
        let item = item(deleted: Self.noon)
        let boundary = Self.noon + Double(days) * day
        #expect(!item.isExpired(now: boundary - 1, after: days))
        #expect(item.isExpired(now: boundary, after: days))
    }

    /// Rounded up, so the last day reads 1.
    @Test func roundsTheDaysLeftUp() {
        let item = item(deleted: Self.noon)
        #expect(item.daysLeft(now: Self.noon, after: 30) == 30)
        #expect(item.daysLeft(now: Self.noon + 1, after: 30) == 30)
        #expect(item.daysLeft(now: Self.noon + day, after: 30) == 29)
        #expect(item.daysLeft(now: Self.noon + 30 * day - 1, after: 30) == 1)
        #expect(item.daysLeft(now: Self.noon + 30 * day, after: 30) == 0)
    }
}
