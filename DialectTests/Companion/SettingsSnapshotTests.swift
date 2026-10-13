import Foundation
import Testing

@testable import Dialect

struct SettingsSnapshotTests {
    static let snapshot = SettingsSnapshot(
        epoch: "E",
        settings: [
            AccentSetting.key: .init(value: .string(RGBColor.dialectGreen.displayP3), version: 2),
            FileSettings.showHiddenKey: .init(value: .bool(true), version: 1),
            FileSettings.undoHistoryKey: .init(
                value: .int(50), version: 3, edit: EditStamp(base: 2, revision: 1)),
            FileSettings.textExtensionsKey: .init(value: .strings(["fnl"]), version: 1),
        ],
        sequence: 3, undoSteps: 7, watchName: "Eir")

    /// Through a property list's bytes, as WatchConnectivity sends it.
    private func sent(_ list: [String: Any]) throws -> [String: Any] {
        let data = try PropertyListSerialization.data(
            fromPropertyList: list, format: .binary, options: 0)
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func roundTrips() throws {
        #expect(
            SettingsSnapshot(propertyList: try sent(Self.snapshot.propertyList)) == Self.snapshot)
    }

    @Test func leavesOutAMissingName() throws {
        var snapshot = Self.snapshot
        snapshot.watchName = nil
        let list = try sent(snapshot.propertyList)
        #expect(list["watchName"] == nil)
        #expect(SettingsSnapshot(propertyList: list) == snapshot)
    }

    /// Each setting stands alone, so the apps can be different versions.
    @Test func dropsUnknownSettingsAndWrongKinds() throws {
        var list = Self.snapshot.propertyList
        var settings = try #require(list["settings"] as? [String: Any])
        settings["editor.fontSize"] = ["value": 14, "version": 1]
        settings[FileSettings.showHiddenKey] = ["value": 1, "version": 1]
        settings[FileSettings.undoHistoryKey] = ["value": 50]
        list["settings"] = settings
        let read = try #require(SettingsSnapshot(propertyList: try sent(list)))
        #expect(
            Set(read.settings.keys) == [AccentSetting.key, FileSettings.textExtensionsKey])
        #expect(read.undoSteps == 7)
    }

    /// A damaged stamp is dropped and its setting kept.
    @Test func dropsADamagedStamp() throws {
        var list = Self.snapshot.propertyList
        var settings = try #require(list["settings"] as? [String: Any])
        settings[FileSettings.undoHistoryKey] = [
            "value": 50, "version": 3, "edit": ["base": 2],
        ]
        list["settings"] = settings
        let read = try #require(SettingsSnapshot(propertyList: try sent(list)))
        #expect(
            read.settings[FileSettings.undoHistoryKey]
                == .init(value: .int(50), version: 3, edit: nil))
    }

    @Test func refusesAnotherFormatWhole() throws {
        var list = Self.snapshot.propertyList
        list["format"] = 2
        #expect(SettingsSnapshot(propertyList: try sent(list)) == nil)
        #expect(SettingsSnapshot.format(of: list) == 2)
    }

    @Test func refusesADamagedSnapshot() throws {
        for key in ["epoch", "settings", "sequence", "undoSteps"] {
            var list = Self.snapshot.propertyList
            list[key] = nil
            #expect(SettingsSnapshot(propertyList: try sent(list)) == nil)
        }
    }

    @Test func readsWhatThePhoneReceived() throws {
        #expect(ReceivedSnapshot(propertyList: [:]) == .none)
        #expect(
            ReceivedSnapshot(propertyList: try sent(Self.snapshot.propertyList))
                == .readable(Self.snapshot))
        var list = Self.snapshot.propertyList
        list["format"] = 2
        #expect(ReceivedSnapshot(propertyList: list) == .otherFormat(newer: true))
        list["format"] = 0
        #expect(ReceivedSnapshot(propertyList: list) == .otherFormat(newer: false))
        list["format"] = 1
        list["epoch"] = nil
        #expect(ReceivedSnapshot(propertyList: list) == .none)
        list["format"] = nil
        #expect(ReceivedSnapshot(propertyList: list) == .none)
    }

    /// One list, so the watch sends and the phone reads the same settings.
    @Test func mirrorsEverySettingWithAScreen() {
        #expect(MirroredSettings.all.count == 13)
        #expect(MirroredSettings.all[FileSettings.textExtensionsKey] == .strings)
        #expect(MirroredSettings.all[FileSettings.recentExtensionsKey] == nil)
    }

    /// A message and a context can cross; the sequence says which is newer.
    @Test func knowsAnOlderSnapshot() {
        var newer = Self.snapshot
        newer.sequence = 4
        // Only the undo history's length changed: no version did.
        newer.undoSteps = 8
        #expect(Self.snapshot.isOlder(than: newer))
        #expect(!newer.isOlder(than: Self.snapshot))
        #expect(!Self.snapshot.isOlder(than: Self.snapshot))

        // Another epoch's sequence can't be compared.
        newer.epoch = "F"
        #expect(!Self.snapshot.isOlder(than: newer))
    }

    @Test func keepsTheNewerOfWhatArrives() {
        var newer = Self.snapshot
        newer.sequence = 4
        let old = ReceivedSnapshot.readable(Self.snapshot)
        let new = ReceivedSnapshot.readable(newer)
        #expect(ReceivedSnapshot.latest(new, over: old) == new)
        #expect(ReceivedSnapshot.latest(old, over: new) == new)
        #expect(ReceivedSnapshot.latest(nil, over: new) == new)
        #expect(ReceivedSnapshot.latest(new, over: .none) == new)
        // A reinstalled watch app starts a new epoch, and its snapshot wins.
        var reinstalled = Self.snapshot
        reinstalled.epoch = "F"
        reinstalled.sequence = 1
        #expect(
            ReceivedSnapshot.latest(.readable(reinstalled), over: new) == .readable(reinstalled))
    }

    /// A message that isn't a snapshot leaves the one held alone.
    @Test func readsOnlySnapshotsFromMessages() throws {
        #expect(ReceivedSnapshot(message: ["ping": true]) == nil)
        #expect(
            ReceivedSnapshot(message: try sent(Self.snapshot.propertyList))
                == .readable(Self.snapshot))
        var other = Self.snapshot.propertyList
        other["format"] = 2
        #expect(ReceivedSnapshot(message: other) == .otherFormat(newer: true))
    }
}
