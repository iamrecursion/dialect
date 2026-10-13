import Foundation
import Testing

@testable import Dialect

/// The watch's rule for the phone's edits: it applies one only if nothing
/// changed the setting on the watch since the phone's snapshot.
struct ApplyEditsTests {
    private let root: TemporaryRoot
    private let mirror: Mirror

    /// What the phone saw: every setting at version 1.
    private let seen: SettingsSnapshot

    private static let hidden = FileSettings.showHiddenKey
    private static let steps = FileSettings.undoHistoryKey

    private static let settings: [String: SettingValue] = [
        hidden: .bool(false),
        steps: .int(20),
        AccentSetting.key: .string(RGBColor.dialectGreen.displayP3),
    ]

    init() throws {
        root = try TemporaryRoot()
        mirror = Mirror(url: root.url.appending(path: "Companion/Mirror.json"))
        seen = try mirror.update(with: Self.settings)
    }

    private func edits(
        _ key: String, _ value: SettingValue, base: Int = 1, revision: Int = 1,
        epoch: String? = nil
    ) -> PhoneEdits {
        return PhoneEdits(
            epoch: epoch ?? seen.epoch,
            edits: [key: .init(value: value, base: base, revision: revision)])
    }

    /// Applies what the rule takes, as the watch does, and returns the values
    /// written.
    @discardableResult
    private func apply(_ edits: PhoneEdits, over current: [String: SettingValue] = settings)
        throws -> [String: SettingValue]
    {
        guard let applied = mirror.applying(edits, over: current) else { return [:] }
        try mirror.record(applied)
        return applied.values
    }

    /// The watch's settings with `applied` written.
    private func current(_ applied: [String: SettingValue]) -> [String: SettingValue] {
        return Self.settings.merging(applied) { $1 }
    }

    private func setting(_ key: String, after applied: [String: SettingValue]) throws
        -> SettingsSnapshot.Versioned?
    {
        return try mirror.update(with: current(applied)).settings[key]
    }

    @Test func appliesAnEditToTheVersionThePhoneSaw() throws {
        let applied = try apply(edits(Self.hidden, .bool(true)))
        #expect(applied == [Self.hidden: .bool(true)])
        #expect(
            try setting(Self.hidden, after: applied)
                == .init(value: .bool(true), version: 2, edit: EditStamp(base: 1, revision: 1)))
    }

    /// A change on the watch the phone hasn't heard of yet still wins.
    @Test func dropsAnEditTheWatchOverruled() throws {
        var changed = Self.settings
        changed[Self.steps] = .int(50)
        #expect(try apply(edits(Self.steps, .int(100)), over: changed).isEmpty)
        #expect(
            try mirror.update(with: changed).settings[Self.steps]
                == .init(value: .int(50), version: 2))
    }

    @Test func dropsAnEditFromAnotherEpoch() throws {
        #expect(try apply(edits(Self.hidden, .bool(true), epoch: "OLD")).isEmpty)
    }

    @Test func dropsAValueItRefuses() throws {
        #expect(try apply(edits(Self.steps, .int(30))).isEmpty)
    }

    @Test func dropsASettingItDoesntHave() throws {
        #expect(try apply(edits(RecentsSettings.showLastKey, .int(10))).isEmpty)
    }

    /// A second change, made before the phone heard of the first.
    @Test func takesALaterRevisionOfAnAppliedEdit() throws {
        let first = try apply(edits(Self.hidden, .bool(true)))
        let applied = try apply(edits(Self.hidden, .bool(false), revision: 2), over: current(first))
        #expect(applied == [Self.hidden: .bool(false)])
        #expect(
            try setting(Self.hidden, after: applied)
                == .init(value: .bool(false), version: 3, edit: EditStamp(base: 1, revision: 2)))
    }

    /// The same edit by message and by context, or an older revision after a
    /// newer one.
    @Test func dropsADuplicateOrAStaleRevision() throws {
        let applied = try apply(edits(Self.hidden, .bool(true), revision: 2))
        let after = current(applied)
        #expect(try apply(edits(Self.hidden, .bool(true), revision: 2), over: after).isEmpty)
        #expect(try apply(edits(Self.hidden, .bool(false), revision: 1), over: after).isEmpty)
        #expect(try setting(Self.hidden, after: applied)?.version == 2)
    }

    /// So the phone sees it handled.
    @Test func raisesTheVersionForTheSameValue() throws {
        let applied = try apply(edits(Self.hidden, .bool(false), revision: 2))
        #expect(
            try setting(Self.hidden, after: applied)
                == .init(value: .bool(false), version: 2, edit: EditStamp(base: 1, revision: 2)))
    }

    @Test func clearsTheStampWhenTheWatchChangesIt() throws {
        try apply(edits(Self.hidden, .bool(true)))
        #expect(
            try mirror.update(with: Self.settings).settings[Self.hidden]
                == .init(value: .bool(false), version: 3))
    }

    /// The edit after a watch change, made against the snapshot that showed it.
    @Test func takesANewEditAfterAStamp() throws {
        try apply(edits(Self.hidden, .bool(true)))
        _ = try mirror.update(with: Self.settings)
        #expect(try apply(edits(Self.hidden, .bool(true), base: 3)) == [Self.hidden: .bool(true)])
    }

    /// In the form the watch writes, so the next update finds nothing to
    /// change.
    @Test func takesAnAccentInTheWrittenForm() throws {
        let color = RGBColor(red: 0.5, green: 0.25, blue: 1).displayP3
        let applied = try apply(edits(AccentSetting.key, .string(color)))
        #expect(applied == [AccentSetting.key: .string(color)])
        #expect(try setting(AccentSetting.key, after: applied)?.version == 2)
        #expect(
            try apply(edits(AccentSetting.key, .string("color(display-p3 0.5 0.25 1)"))).isEmpty)
    }

    /// A change on the watch after an applied edit wins over the edit's next
    /// revision.
    @Test func dropsALaterRevisionAfterAWatchChange() throws {
        try apply(edits(Self.hidden, .bool(true)))
        #expect(try apply(edits(Self.hidden, .bool(false), revision: 2)).isEmpty)
        #expect(
            try mirror.update(with: Self.settings).settings[Self.hidden]
                == .init(value: .bool(false), version: 3))
    }

    /// Dialect stopping between writing the settings and the record: the next
    /// snapshot settles the edit on the phone.
    @Test func settlesAnEditWhoseRecordWasntWritten() throws {
        let sent = edits(Self.hidden, .bool(true))
        let applied = try #require(mirror.applying(sent, over: Self.settings))
        let snapshot = try mirror.update(with: current(applied.values))
        #expect(sent.outcome(of: Self.hidden, in: snapshot) == .done)
    }

    @Test func appliesEachSettingApart() throws {
        var both = edits(Self.hidden, .bool(true))
        both.edits[Self.steps] = .init(value: .int(50), base: 7, revision: 1)
        #expect(try apply(both) == [Self.hidden: .bool(true)])
    }

    /// A change on the watch not yet sent is recorded with the edit, once.
    @Test func recordsAnUnsentWatchChangeOnce() throws {
        var changed = Self.settings
        changed[Self.steps] = .int(50)
        let applied = try apply(edits(Self.hidden, .bool(true)), over: changed)
        let after = try mirror.update(with: changed.merging(applied) { $1 })
        #expect(after.settings[Self.steps] == .init(value: .int(50), version: 2))
        #expect(after.settings[Self.hidden]?.version == 2)
    }
}
