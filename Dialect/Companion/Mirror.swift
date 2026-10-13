import Foundation

/// What the watch last sent the phone: each mirrored setting's value, version
/// and stamp, and the last snapshot's sequence number. It's kept in a file
/// because writing it to `UserDefaults` would post a settings change which
/// could cause an overwrite in case of a conflict.
struct Mirror: Sendable {
    /// The file it's kept in, written whole each time.
    let url: URL

    static let standard = Mirror(
        url: URL.applicationSupportDirectory.appending(
            path: "Companion/Mirror.json", directoryHint: .notDirectory))

    fileprivate struct Record: Codable, Equatable {
        var format = 1
        var epoch: String
        var settings: [String: Entry]
        var sequence = 0

        struct Entry: Codable, Equatable {
            var value: SettingValue
            var version: Int

            /// The phone edit that made this version; `nil` if it was the
            /// watch.
            var edit: EditStamp?
        }

        /// Takes each setting whose value differs in `current` as a change on
        /// the watch: raises its version (a new setting starts at 1) and clears
        /// its stamp.
        func following(_ current: [String: SettingValue]) -> Record {
            var record = self
            for (key, value) in current where settings[key]?.value != value {
                record.settings[key] = Entry(
                    value: value, version: (settings[key]?.version ?? 0) + 1)
            }
            return record
        }
    }

    /// Records each change the watch made to the settings, and writes the
    /// record if anything changed. A record that can't be read starts afresh
    /// under a new epoch.
    func update(with current: [String: SettingValue]) throws -> SettingsSnapshot {
        let old = read()
        let record = (old ?? Record(epoch: UUID().uuidString, settings: [:])).following(current)
        if record != old { try write(record) }
        // A setting no longer mirrored keeps its version in the record, so it carries on from there
        // if it comes back.
        return SettingsSnapshot(
            epoch: record.epoch,
            settings: record.settings.filter { current[$0.key] != nil }.mapValues {
                SettingsSnapshot.Versioned(value: $0.value, version: $0.version, edit: $0.edit)
            }, sequence: record.sequence)
    }

    /// The values the watch takes from the phone's edits, and the record to
    /// write once they're in the settings.
    struct Applied: Sendable {
        let values: [String: SettingValue]
        fileprivate let record: Record
    }

    /// The phone's edits the watch takes over `current`, with its unsent
    /// changes recorded first; `nil` if it takes none.
    ///
    /// It takes an edit to a setting it has, with a value it accepts, from the
    /// record's epoch, if:
    /// - when the setting's stamp has the edit's `base`: the edit's revision is
    ///   higher, a later revision of the edit the watch applied;
    /// - otherwise: the setting's version is still the edit's `base`.
    ///
    /// Each edit taken raises its setting's version and stamps it, even for the
    /// same value, so the phone sees it handled.
    func applying(_ edits: PhoneEdits, over current: [String: SettingValue]) -> Applied? {
        guard let old = read(), old.epoch == edits.epoch else { return nil }
        // A change on the watch not yet sent still wins.
        let record = old.following(current)
        var next = record
        var values: [String: SettingValue] = [:]
        for (key, edit) in edits.edits where MirroredSettings.accepts(edit.value, for: key) {
            guard let entry = record.settings[key], current[key] != nil else { continue }
            let takes =
                if let stamp = entry.edit, stamp.base == edit.base {
                    edit.revision > stamp.revision
                } else {
                    entry.version == edit.base
                }
            guard takes else { continue }
            next.settings[key] = Record.Entry(
                value: edit.value, version: entry.version + 1, edit: edit.stamp)
            values[key] = edit.value
        }
        return values.isEmpty ? nil : Applied(values: values, record: next)
    }

    /// Writes the record of edits applied, once their values are in the
    /// settings.
    func record(_ applied: Applied) throws {
        try write(applied.record)
    }

    /// Raises the sequence number for a snapshot about to be sent, and records
    /// it.
    func nextSequence() throws -> Int {
        guard var record = read() else { throw CocoaError(.fileReadCorruptFile) }
        record.sequence += 1
        try write(record)
        return record.sequence
    }

    private func write(_ record: Record) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }

    private func read() -> Record? {
        guard let data = try? Data(contentsOf: url),
            let record = try? JSONDecoder().decode(Record.self, from: data),
            record.format == 1
        else { return nil }
        return record
    }
}
