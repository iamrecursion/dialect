import Foundation

/// The phone's changes to the watch's settings, queue for the watch to receive.
/// They live in the phone's application context, and go by message while the
/// watch is reachable.
///
/// The watch applies an edit only if nothing changed the setting on the watch
/// since the phone's snapshot: the watch wins a disagreement. Each new snapshot
/// says what became of each edit (`outcome(of:in:)`).
struct PhoneEdits: Equatable, Sendable {
    /// The format's number. Edits in another format are refused whole.
    static let format = 1

    /// The epoch of the snapshot the edits were made against.
    var epoch: String
    var edits: [String: Edit]

    struct Edit: Equatable, Sendable {
        var value: SettingValue

        /// The setting's version in the snapshot the phone edited.
        var base: Int

        /// 1 for a new edit, raised each time the user changes the setting
        /// again while the edit waits.
        var revision: Int

        var stamp: EditStamp { EditStamp(base: base, revision: revision) }
    }

    static let empty = PhoneEdits(epoch: "", edits: [:])

    /// The edit's value for `key`, if one waits.
    func value(_ key: String) -> SettingValue? {
        return edits[key]?.value
    }

    /// With `key` changed to `value`. A waiting edit takes the value as its
    /// next revision, even when it's the snapshot's value, as the watch may
    /// have applied the edit already. Otherwise a new edit is made against the
    /// snapshot, unless the value is the snapshot's.
    func editing(_ key: String, to value: SettingValue, against snapshot: SettingsSnapshot)
        -> PhoneEdits
    {
        var next = self
        if var edit = edits[key] {
            guard edit.value != value else { return self }
            edit.value = value
            edit.revision += 1
            next.edits[key] = edit
        } else if let setting = snapshot.settings[key], setting.value != value {
            // Waiting edits share the snapshot's epoch: a snapshot from another epoch settles them
            // all.
            next.epoch = snapshot.epoch
            next.edits[key] = Edit(value: value, base: setting.version, revision: 1)
        }
        return next
    }

    enum Outcome: Equatable, Sendable {
        /// The watch hasn't handled it, has applied an earlier revision, or the
        /// snapshot is older than the one edited.
        case waiting

        /// Applied, made on the watch too, or no longer mirrored: there's
        /// nothing to tell the user.
        case done

        /// The setting took another value on the watch, so the edit was
        /// dropped: the user changed it there, an earlier edit did, or the
        /// watch app was reinstalled.
        case changedOnWatch
    }

    /// What became of the edit for `key`, from a new snapshot.
    func outcome(of key: String, in snapshot: SettingsSnapshot) -> Outcome {
        guard let edit = edits[key], let setting = snapshot.settings[key] else { return .done }
        if snapshot.epoch == epoch {
            // Not handled yet, or a snapshot older than the one edited: versions only rise.
            if setting.version <= edit.base { return .waiting }
            if let stamp = setting.edit, stamp.base == edit.base, stamp.revision < edit.revision {
                return .waiting
            }
        }
        // The watch has moved past the edit's base: by this edit, by a change on the watch, or by
        // an earlier edit sharing this one's stamp, as this one was made against an older snapshot.
        // Only the values tell these apart.
        return setting.value == edit.value ? .done : .changedOnWatch
    }

    /// The edits still waiting after a new snapshot, and the settings whose
    /// edits the watch dropped for another value.
    func resolved(by snapshot: SettingsSnapshot) -> (PhoneEdits, changedOnWatch: Set<String>) {
        var next = self
        var changed = Set<String>()
        for key in edits.keys {
            switch outcome(of: key, in: snapshot) {
            case .waiting: continue
            case .done: next.edits[key] = nil
            case .changedOnWatch:
                next.edits[key] = nil
                changed.insert(key)
            }
        }
        return (next, changed)
    }

    var propertyList: [String: Any] {
        return [
            "format": Self.format,
            "epoch": epoch,
            "edits": edits.mapValues { edit -> [String: Any] in
                ["value": edit.value.propertyList, "base": edit.base, "revision": edit.revision]
            },
        ]
    }

    /// `nil` for another format, or without an epoch or edits. An edit to a
    /// setting that's not mirrored, or a damaged one, is dropped and the rest
    /// kept.
    init?(propertyList list: [String: Any]) {
        guard SettingsSnapshot.format(of: list) == Self.format,
            let epoch = list["epoch"] as? String,
            let edits = list["edits"] as? [String: Any]
        else { return nil }
        self.epoch = epoch
        self.edits = edits.reduce(into: [:]) { kept, entry in
            guard let kind = MirroredSettings.all[entry.key],
                let fields = entry.value as? [String: Any],
                let value = fields["value"].flatMap({ SettingValue(propertyList: $0, as: kind) }),
                let stamp = EditStamp(propertyList: fields)
            else { return }
            kept[entry.key] = Edit(value: value, base: stamp.base, revision: stamp.revision)
        }
    }

    init(epoch: String, edits: [String: Edit]) {
        self.epoch = epoch
        self.edits = edits
    }
}
