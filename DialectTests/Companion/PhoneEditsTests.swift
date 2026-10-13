import Foundation
import Testing

@testable import Dialect

/// The phone's edits: their format, how they coalesce, and what the phone makes
/// of each new snapshot.
struct PhoneEditsTests {
    private static let hidden = FileSettings.showHiddenKey
    private static let steps = FileSettings.undoHistoryKey

    /// Hidden Files off at version 4, Undo History 20 at version 2.
    private static let snapshot = SettingsSnapshot(
        epoch: "E",
        settings: [
            hidden: .init(value: .bool(false), version: 4),
            steps: .init(value: .int(20), version: 2),
        ])

    /// Through a property list's bytes, as WatchConnectivity sends it.
    private func sent(_ list: [String: Any]) throws -> [String: Any] {
        let data = try PropertyListSerialization.data(
            fromPropertyList: list, format: .binary, options: 0)
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// The snapshot with `key` at `value` and `version`, stamped with `edit` if
    /// given.
    private func snapshot(
        _ key: String, _ value: SettingValue, version: Int, edit: EditStamp? = nil,
        epoch: String = "E"
    ) -> SettingsSnapshot {
        var snapshot = Self.snapshot
        snapshot.epoch = epoch
        snapshot.settings[key] = .init(value: value, version: version, edit: edit)
        return snapshot
    }

    private func turningHiddenOn() -> PhoneEdits {
        return PhoneEdits.empty.editing(Self.hidden, to: .bool(true), against: Self.snapshot)
    }

    // MARK: Format

    @Test func roundTrips() throws {
        let edits = turningHiddenOn().editing(Self.steps, to: .int(50), against: Self.snapshot)
        #expect(PhoneEdits(propertyList: try sent(edits.propertyList)) == edits)
        #expect(PhoneEdits(propertyList: try sent(PhoneEdits.empty.propertyList)) == .empty)
    }

    @Test func dropsUnknownSettingsAndDamagedEdits() throws {
        var list = turningHiddenOn().propertyList
        var edits = try #require(list["edits"] as? [String: Any])
        edits["editor.fontSize"] = ["value": 14, "base": 1, "revision": 1]
        edits[Self.steps] = ["value": true, "base": 2, "revision": 1]
        edits[FileSettings.foldersFirstKey] = ["value": true, "base": 2]
        list["edits"] = edits
        #expect(PhoneEdits(propertyList: try sent(list)) == turningHiddenOn())
    }

    @Test func refusesAnotherFormatOrDamageWhole() throws {
        var list = turningHiddenOn().propertyList
        list["format"] = 2
        #expect(PhoneEdits(propertyList: try sent(list)) == nil)
        for key in ["format", "epoch", "edits"] {
            var list = turningHiddenOn().propertyList
            list[key] = nil
            #expect(PhoneEdits(propertyList: try sent(list)) == nil)
        }
        #expect(PhoneEdits(propertyList: [:]) == nil)
    }

    // MARK: Coalescing

    @Test func makesAnEditAgainstTheSnapshot() {
        let edits = turningHiddenOn()
        #expect(edits.epoch == "E")
        #expect(edits.edits[Self.hidden] == .init(value: .bool(true), base: 4, revision: 1))
        #expect(edits.value(Self.hidden) == .bool(true))
    }

    @Test func makesNoEditForTheSnapshotsValue() {
        #expect(
            PhoneEdits.empty.editing(Self.hidden, to: .bool(false), against: Self.snapshot)
                == .empty)
    }

    @Test func makesNoEditForASettingTheWatchDidntSend() {
        let edits = PhoneEdits.empty.editing(
            FileSettings.foldersFirstKey, to: .bool(false), against: Self.snapshot)
        #expect(edits == .empty)
    }

    /// A second change keeps the first `base` and raises the revision.
    @Test func revisesAWaitingEdit() {
        let edits = turningHiddenOn()
            .editing(Self.hidden, to: .bool(false), against: Self.snapshot)
        #expect(edits.edits[Self.hidden] == .init(value: .bool(false), base: 4, revision: 2))
        // The same value again changes nothing.
        #expect(edits.editing(Self.hidden, to: .bool(false), against: Self.snapshot) == edits)
    }

    @Test func keepsEachSettingApart() {
        let edits = turningHiddenOn().editing(Self.steps, to: .int(50), against: Self.snapshot)
        #expect(edits.edits[Self.hidden]?.revision == 1)
        #expect(edits.edits[Self.steps] == .init(value: .int(50), base: 2, revision: 1))
    }

    // MARK: Outcomes

    private func outcome(_ edits: PhoneEdits, _ snapshot: SettingsSnapshot) -> PhoneEdits.Outcome {
        return edits.outcome(of: Self.hidden, in: snapshot)
    }

    @Test func waitsUntilTheWatchHandlesIt() {
        #expect(outcome(turningHiddenOn(), Self.snapshot) == .waiting)
    }

    /// At launch, the session can hand the phone an old snapshot before the
    /// newest.
    @Test func waitsOnAnOlderSnapshot() {
        #expect(
            outcome(turningHiddenOn(), snapshot(Self.hidden, .bool(false), version: 3)) == .waiting)
    }

    @Test func dropsAnAppliedEditQuietly() {
        let applied = snapshot(
            Self.hidden, .bool(true), version: 5, edit: EditStamp(base: 4, revision: 1))
        #expect(outcome(turningHiddenOn(), applied) == .done)
    }

    /// At launch the phone can show an old snapshot, from before an earlier
    /// edit the watch applied; a new edit then shares that edit's stamp, and
    /// the watch drops it.
    @Test func saysWhenAnEditOnAnOldSnapshotIsDropped() {
        let earlier = snapshot(
            Self.hidden, .bool(true), version: 5, edit: EditStamp(base: 4, revision: 1))
        let edits = PhoneEdits.empty.editing(
            Self.hidden, to: .bool(false), against: snapshot(Self.hidden, .bool(true), version: 4))
        #expect(outcome(edits, earlier) == .changedOnWatch)
    }

    /// The watch applied the first change, and the second is on its way.
    @Test func waitsWhileAnEarlierRevisionIsApplied() {
        let revised = turningHiddenOn().editing(
            Self.hidden, to: .bool(false), against: Self.snapshot)
        let applied = snapshot(
            Self.hidden, .bool(true), version: 5, edit: EditStamp(base: 4, revision: 1))
        #expect(outcome(revised, applied) == .waiting)
        let second = snapshot(
            Self.hidden, .bool(false), version: 6, edit: EditStamp(base: 4, revision: 2))
        #expect(outcome(revised, second) == .done)
    }

    @Test func dropsAnEditTheWatchMadeTooQuietly() {
        #expect(outcome(turningHiddenOn(), snapshot(Self.hidden, .bool(true), version: 5)) == .done)
    }

    @Test func saysWhenTheWatchChangedIt() {
        // The watch turned it on and off again.
        #expect(
            outcome(turningHiddenOn(), snapshot(Self.hidden, .bool(false), version: 6))
                == .changedOnWatch)
        // A stamp from another edit, after the watch changed it.
        let other = snapshot(
            Self.hidden, .bool(false), version: 7, edit: EditStamp(base: 6, revision: 1))
        #expect(outcome(turningHiddenOn(), other) == .changedOnWatch)
    }

    /// A reinstalled watch app's versions start again, so they can't be
    /// compared.
    @Test func settlesEveryEditAgainstAnotherEpoch() {
        let reinstalled = snapshot(Self.hidden, .bool(false), version: 4, epoch: "F")
        #expect(outcome(turningHiddenOn(), reinstalled) == .changedOnWatch)
        let same = snapshot(Self.hidden, .bool(true), version: 4, epoch: "F")
        #expect(outcome(turningHiddenOn(), same) == .done)
    }

    @Test func dropsAnEditForASettingTheWatchNoLongerSends() {
        var gone = Self.snapshot
        gone.settings[Self.hidden] = nil
        #expect(outcome(turningHiddenOn(), gone) == .done)
    }

    @Test func resolvesEachEditByOutcome() {
        let edits = turningHiddenOn().editing(Self.steps, to: .int(50), against: Self.snapshot)
        #expect(edits.resolved(by: Self.snapshot) == (edits, []))

        var next = snapshot(Self.hidden, .bool(false), version: 5)
        next.settings[Self.steps] = .init(
            value: .int(50), version: 3, edit: EditStamp(base: 2, revision: 1))
        let (remaining, changed) = edits.resolved(by: next)
        #expect(remaining.edits.isEmpty)
        #expect(changed == [Self.hidden])
    }
}
