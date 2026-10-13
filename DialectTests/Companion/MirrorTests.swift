import Foundation
import Testing

@testable import Dialect

/// The watch's versions: raised when a value changes, and only then.
struct MirrorTests {
    private let root: TemporaryRoot
    private let mirror: Mirror

    init() throws {
        root = try TemporaryRoot()
        mirror = Mirror(url: root.url.appending(path: "Companion/Mirror.json"))
    }

    private static let settings: [String: SettingValue] = [
        FileSettings.showHiddenKey: .bool(false),
        FileSettings.undoHistoryKey: .int(20),
        FileSettings.textExtensionsKey: .strings([]),
    ]

    private func versions(_ snapshot: SettingsSnapshot) -> [String: Int] {
        return snapshot.settings.mapValues(\.version)
    }

    private func modified() throws -> Date? {
        return try FileManager.default.attributesOfItem(atPath: mirror.url.path)[
            .modificationDate] as? Date
    }

    @Test func startsEachSettingAtOne() throws {
        let snapshot = try mirror.update(with: Self.settings)
        #expect(versions(snapshot) == Self.settings.mapValues { _ in 1 })
        #expect(snapshot.settings.mapValues(\.value) == Self.settings)
        #expect(UUID(uuidString: snapshot.epoch) != nil)
    }

    @Test func raisesOnlyWhatChanged() throws {
        let first = try mirror.update(with: Self.settings)
        var changed = Self.settings
        changed[FileSettings.showHiddenKey] = .bool(true)
        let second = try mirror.update(with: changed)
        #expect(second.epoch == first.epoch)
        #expect(second.settings[FileSettings.showHiddenKey]?.version == 2)
        #expect(second.settings[FileSettings.undoHistoryKey]?.version == 1)

        // Changing it back is another change.
        let third = try mirror.update(with: Self.settings)
        #expect(third.settings[FileSettings.showHiddenKey]?.version == 3)
        #expect(third.settings[FileSettings.showHiddenKey]?.value == .bool(false))
    }

    /// Versions are read back from the file, as after a relaunch.
    @Test func keepsVersionsAcrossReads() throws {
        var changed = Self.settings
        changed[FileSettings.undoHistoryKey] = .int(50)
        _ = try mirror.update(with: Self.settings)
        _ = try mirror.update(with: changed)
        let again = try Mirror(url: mirror.url).update(with: changed)
        #expect(again.settings[FileSettings.undoHistoryKey]?.version == 2)
    }

    @Test func doesNotWriteWhenNothingChanged() throws {
        _ = try mirror.update(with: Self.settings)
        let written = try modified()
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: mirror.url.path)
        _ = try mirror.update(with: Self.settings)
        #expect(try modified() == Date(timeIntervalSince1970: 0))
        #expect(written != nil)
    }

    @Test func startsANewEpochForADamagedFile() throws {
        let first = try mirror.update(with: Self.settings)
        try Data("{".utf8).write(to: mirror.url)
        let second = try mirror.update(with: Self.settings)
        #expect(second.epoch != first.epoch)
        #expect(versions(second) == Self.settings.mapValues { _ in 1 })
    }

    /// A new setting starts at 1; one no longer sent keeps its version, never
    /// falling if it returns.
    @Test func addsAndKeepsSettings() throws {
        var changed = Self.settings
        changed[FileSettings.showHiddenKey] = .bool(true)
        _ = try mirror.update(with: Self.settings)
        _ = try mirror.update(with: changed)

        var fewer = changed
        fewer[FileSettings.showHiddenKey] = nil
        fewer[RecentsSettings.showLastKey] = .int(5)
        let without = try mirror.update(with: fewer)
        #expect(without.settings[FileSettings.showHiddenKey] == nil)
        #expect(without.settings[RecentsSettings.showLastKey]?.version == 1)

        let back = try mirror.update(with: Self.settings)
        #expect(back.settings[FileSettings.showHiddenKey]?.version == 3)
    }

    @Test func countsTheSnapshotsSent() throws {
        #expect(try mirror.update(with: Self.settings).sequence == 0)
        #expect(try mirror.nextSequence() == 1)
        #expect(try mirror.nextSequence() == 2)
        #expect(try Mirror(url: mirror.url).update(with: Self.settings).sequence == 2)
    }
}
