import Foundation
import Testing

@testable import Dialect

/// Sorting and grouping a folder's items into sections.
struct FolderArrangementTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86400

    private func item(
        _ name: String, _ kind: FileKind = .text, size: Int64? = nil, modified: Date? = nil,
        created: Date? = nil
    ) -> FileItem {
        let isDirectory = kind == .folder || kind == .session
        return FileItem(
            path: FilePath(components: [name]), kind: kind, isDirectory: isDirectory,
            size: isDirectory ? nil : size, created: created, modified: modified,
            isReadOnly: false)
    }

    private func arrange(
        _ items: [FileItem], _ sort: FolderViewSettings.SortKey = .name, ascending: Bool = true,
        grouping: FolderViewSettings.Grouping = .none, foldersFirst: Bool = true,
        sizes: [FilePath: Int64] = [:]
    ) -> [FileSection] {
        return FolderArrangement.sections(
            items,
            settings: FolderViewSettings(sort: sort, ascending: ascending, grouping: grouping),
            foldersFirst: foldersFirst, now: now, sizes: sizes)
    }

    /// The names in one ungrouped section.
    private func names(_ sections: [FileSection]) -> [String] {
        #expect(sections.count == 1)
        #expect(sections.first?.group == nil)
        return sections.first?.items.map(\.name) ?? []
    }

    private func layout(_ sections: [FileSection]) -> [String] {
        return sections.map { section in
            let title = section.group.map { String(localized: $0.title) } ?? "-"
            return "\(title): " + section.items.map(\.name).joined(separator: " ")
        }
    }

    // MARK: Sorting

    @Test func sortsNamesNaturallyAndCaseInsensitively() {
        let items = ["file10.txt", "File2.txt", "file1.txt", "apple.txt", "Banana.txt"]
            .map { item($0) }
        #expect(
            names(arrange(items))
                == ["apple.txt", "Banana.txt", "file1.txt", "File2.txt", "file10.txt"])
        #expect(
            names(arrange(items, ascending: false))
                == ["file10.txt", "File2.txt", "file1.txt", "Banana.txt", "apple.txt"])
    }

    @Test func sortsByModifiedWithMissingDatesLast() {
        let items = [
            item("old", modified: now - 10 * day), item("none"), item("new", modified: now),
            item("mid", modified: now - day),
        ]
        #expect(names(arrange(items, .modified)) == ["old", "mid", "new", "none"])
        #expect(
            names(arrange(items, .modified, ascending: false)) == ["new", "mid", "old", "none"])
    }

    @Test func sortsByCreated() {
        let items = [
            item("b", created: now), item("a", created: now - day), item("c"),
        ]
        #expect(names(arrange(items, .created)) == ["a", "b", "c"])
        #expect(names(arrange(items, .created, ascending: false)) == ["b", "a", "c"])
    }

    /// Folders and sessions sort by their totals once known, and until then
    /// after everything whose size is known.
    @Test func sortsBySizeWithUnknownFolderSizesLast() {
        let folder = item("folder", .folder)
        let session = item("demo.dial", .session)
        let pending = item("pending", .folder)
        let items = [
            item("big", size: 900), folder, item("small", size: 10), session, pending,
        ]
        let sizes = [folder.path: 500, session.path: Int64(5)]
        #expect(
            names(arrange(items, .size, foldersFirst: false, sizes: sizes))
                == ["demo.dial", "small", "folder", "big", "pending"])
        #expect(
            names(arrange(items, .size, ascending: false, foldersFirst: false, sizes: sizes))
                == ["big", "folder", "small", "demo.dial", "pending"])
    }

    /// Equal keys fall back to the name, so the order never shuffles.
    @Test func breaksTiesByName() {
        let items = [item("b", size: 1), item("c", size: 1), item("a", size: 1)]
        #expect(names(arrange(items, .size)) == ["a", "b", "c"])
        #expect(names(arrange(items, .size, ascending: false)) == ["c", "b", "a"])
    }

    // MARK: No grouping

    /// Sessions aren't folders for Folders First: they sort among files.
    @Test func putsFoldersFirst() {
        let items = [
            item("b.txt"), item("z", .folder), item("demo.dial", .session), item("a", .folder),
        ]
        #expect(names(arrange(items)) == ["a", "z", "b.txt", "demo.dial"])
        #expect(names(arrange(items, ascending: false)) == ["z", "a", "demo.dial", "b.txt"])
        #expect(names(arrange(items, foldersFirst: false)) == ["a", "b.txt", "demo.dial", "z"])
    }

    @Test func anEmptyFolderHasNoSections() {
        #expect(arrange([]).isEmpty)
        #expect(arrange([], grouping: .kind).isEmpty)
        #expect(arrange([], grouping: .modified).isEmpty)
    }

    // MARK: Group by Kind

    private var mixed: [FileItem] {
        return [
            item("photo.png", .image), item("notes", .folder), item("readme", .otherText),
            item("blob.bin", .binary), item("prelude.scm", .scheme), item("demo.dial", .session),
            item("clip.mp4", .video), item("notes.md", .text), item("archive", .folder),
        ]
    }

    /// With Folders First off, Folders sits alphabetically under F; on, it's at
    /// the top.
    @Test func groupsByKindAlphabetically() {
        #expect(
            layout(arrange(mixed, grouping: .kind, foldersFirst: false)) == [
                "Folders: archive notes", "Images: photo.png", "Other: blob.bin readme",
                "Scheme: prelude.scm", "Sessions: demo.dial", "Text: notes.md",
                "Videos: clip.mp4",
            ])
        #expect(
            layout(
                arrange(mixed.filter { $0.kind != .image }, grouping: .kind, foldersFirst: false)
            )
            .first == "Folders: archive notes")
    }

    @Test func descendingReversesKindGroups() {
        #expect(
            layout(arrange(mixed, ascending: false, grouping: .kind, foldersFirst: false)) == [
                "Videos: clip.mp4", "Text: notes.md", "Sessions: demo.dial",
                "Scheme: prelude.scm", "Other: readme blob.bin", "Images: photo.png",
                "Folders: notes archive",
            ])
    }

    @Test func foldersFirstPutsTheFoldersGroupOnTop() {
        let sections = arrange(mixed, ascending: false, grouping: .kind)
        #expect(layout(sections).first == "Folders: notes archive")
        #expect(layout(sections)[1] == "Videos: clip.mp4")
    }

    @Test func dropsEmptyKindGroups() {
        let items = [item("a.md"), item("b.scm", .scheme)]
        #expect(layout(arrange(items, grouping: .kind)) == ["Scheme: b.scm", "Text: a.md"])
    }

    // MARK: Group by Modified

    /// Rolling windows counted back from now; "under 24 hours" excludes exactly
    /// 24 hours.
    @Test func bucketsByAge() {
        #expect(FolderArrangement.bucket(for: now, now: now) == .lastDay)
        #expect(FolderArrangement.bucket(for: now + hour, now: now) == .lastDay)
        #expect(FolderArrangement.bucket(for: now - day + 1, now: now) == .lastDay)
        #expect(FolderArrangement.bucket(for: now - day, now: now) == .last2Days)
        #expect(FolderArrangement.bucket(for: now - 2 * day + 1, now: now) == .last2Days)
        #expect(FolderArrangement.bucket(for: now - 2 * day, now: now) == .lastWeek)
        #expect(FolderArrangement.bucket(for: now - 7 * day, now: now) == .last30Days)
        #expect(FolderArrangement.bucket(for: now - 30 * day + 1, now: now) == .last30Days)
        #expect(FolderArrangement.bucket(for: now - 30 * day, now: now) == .older)
        #expect(FolderArrangement.bucket(for: nil, now: now) == .older)
    }

    private var dated: [FileItem] {
        return [
            item("today.md", modified: now - hour), item("dir", .folder, modified: now - 2 * hour),
            item("yesterday.md", modified: now - 30 * hour),
            item("week.md", modified: now - 4 * day),
            item("month.md", modified: now - 10 * day), item("old.md", modified: now - 60 * day),
            item("undated.md"), item("older", .folder, modified: now - 90 * day),
        ]
    }

    @Test func groupsByModified() {
        #expect(
            layout(arrange(dated, grouping: .modified)) == [
                "Last Day: dir today.md", "Last 2 Days: yesterday.md", "Last Week: week.md",
                "Last 30 Days: month.md", "Older: older old.md undated.md",
            ])
    }

    @Test func descendingFlipsBuckets() {
        #expect(
            layout(arrange(dated, ascending: false, grouping: .modified)) == [
                "Older: older undated.md old.md", "Last 30 Days: month.md", "Last Week: week.md",
                "Last 2 Days: yesterday.md", "Last Day: dir today.md",
            ])
    }

    @Test func foldersFirstWithinEachBucket() {
        #expect(
            layout(arrange(dated, grouping: .modified, foldersFirst: false)) == [
                "Last Day: dir today.md", "Last 2 Days: yesterday.md", "Last Week: week.md",
                "Last 30 Days: month.md", "Older: old.md older undated.md",
            ])
        let sorted = arrange(dated, .modified, grouping: .modified, foldersFirst: true)
        #expect(layout(sorted).last == "Older: older old.md undated.md")
    }

    @Test func modifiedBucketTitles() {
        #expect(
            ModifiedBucket.allCases.map(\.title.key) == [
                "Last Day", "Last 2 Days", "Last Week", "Last 30 Days", "Older",
            ])
    }

    // MARK: Size

    /// Listing and arranging 2,000 items stays quick. Their extensions are
    /// known, so nothing is sniffed; sniffing still runs inside the listing, so
    /// a folder of unknown files is slower.
    @Test func listsAndArrangesAHugeFolderQuickly() throws {
        let root = try TemporaryRoot()
        for index in 0..<2000 {
            try root.file("big/file\(index).txt")
        }
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            let items = try FileListing.items(
                in: FilePath(components: ["big"]), root: root.url, showHidden: false,
                textExtensions: [])
            #expect(items.count == 2000)
            _ = arrange(items, grouping: .kind)
            _ = arrange(items, .modified, grouping: .modified)
        }
        #expect(elapsed < .milliseconds(500), "\(elapsed)")
    }
}
