import Foundation

/// The watch's settings, as it sends them to the phone in its application
/// context and in messages.
///
/// It holds settings and the undo history's length, never files or their names.
struct SettingsSnapshot: Equatable, Sendable {
    /// The format's number. A snapshot in another format is refused whole.
    static let format = 1

    /// The count the versions belong to. A reinstalled watch app starts a new
    /// epoch, counting versions from 1.
    var epoch: String

    /// The watch's effective values, by key, each with its version.
    var settings: [String: Versioned]

    /// Raised by the watch with each snapshot it sends, so the phone can tell
    /// which of two is newer.
    var sequence = 0

    /// Steps in Undo and Redo together.
    var undoSteps = 0

    /// The watch's name, as watchOS gives it.
    var watchName: String?

    struct Versioned: Equatable, Sendable {
        var value: SettingValue

        /// Raised by the watch whenever the value changes, and whenever it
        /// applies an edit from the phone.
        var version: Int

        /// The phone edit that made this version; `nil` if the watch made it.
        var edit: EditStamp?
    }

    func value(_ key: String) -> SettingValue? {
        return settings[key]?.value
    }

    /// Whether the watch sent this before `other`. A message and a context can
    /// arrive out of order; snapshots from different epochs can't be compared.
    func isOlder(than other: SettingsSnapshot) -> Bool {
        return epoch == other.epoch && sequence < other.sequence
    }

    var propertyList: [String: Any] {
        var list: [String: Any] = [
            "format": Self.format,
            "epoch": epoch,
            "settings": settings.mapValues { versioned -> [String: Any] in
                var entry: [String: Any] = [
                    "value": versioned.value.propertyList, "version": versioned.version,
                ]
                entry["edit"] = versioned.edit?.propertyList
                return entry
            },
            "sequence": sequence,
            "undoSteps": undoSteps,
        ]
        list["watchName"] = watchName
        return list
    }

    /// `nil` for another format or a damaged snapshot. A setting that's not
    /// mirrored, or holds the wrong kind of value, is dropped and the rest
    /// kept, so the two apps can be different versions; a damaged stamp is
    /// dropped and its setting kept.
    init?(propertyList list: [String: Any]) {
        guard Self.format(of: list) == Self.format,
            let epoch = list["epoch"] as? String,
            let settings = list["settings"] as? [String: Any],
            let sequence = SettingValue(propertyList: list["sequence"] as Any, as: .int)?.int,
            let undoSteps = SettingValue(propertyList: list["undoSteps"] as Any, as: .int)?.int
        else { return nil }
        self.epoch = epoch
        self.settings = settings.reduce(into: [:]) { kept, entry in
            guard let kind = MirroredSettings.all[entry.key],
                let fields = entry.value as? [String: Any],
                let value = fields["value"].flatMap({ SettingValue(propertyList: $0, as: kind) }),
                let version = fields["version"].flatMap({ SettingValue(propertyList: $0, as: .int) }
                )?
                .int
            else { return }
            kept[entry.key] = Versioned(
                value: value, version: version,
                edit: (fields["edit"] as? [String: Any]).flatMap(EditStamp.init(propertyList:)))
        }
        self.sequence = sequence
        self.undoSteps = undoSteps
        self.watchName = list["watchName"] as? String
    }

    init(
        epoch: String, settings: [String: Versioned], sequence: Int = 0, undoSteps: Int = 0,
        watchName: String? = nil
    ) {
        self.epoch = epoch
        self.settings = settings
        self.sequence = sequence
        self.undoSteps = undoSteps
        self.watchName = watchName
    }

    /// A snapshot's format, if it has one.
    static func format(of list: [String: Any]) -> Int? {
        return list["format"].flatMap { SettingValue(propertyList: $0, as: .int) }?.int
    }
}

/// Which edit from the phone made a setting's version: the edit's `base` and
/// `revision`.
struct EditStamp: Hashable, Sendable, Codable {
    var base: Int
    var revision: Int

    var propertyList: [String: Any] {
        return ["base": base, "revision": revision]
    }

    init(base: Int, revision: Int) {
        self.base = base
        self.revision = revision
    }

    init?(propertyList list: [String: Any]) {
        guard let base = list["base"].flatMap({ SettingValue(propertyList: $0, as: .int)?.int }),
            let revision = list["revision"].flatMap({
                SettingValue(propertyList: $0, as: .int)?.int
            })
        else { return nil }
        self.init(base: base, revision: revision)
    }
}
