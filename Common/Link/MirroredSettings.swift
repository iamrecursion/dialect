import Foundation

/// The settings the watch shows the phone, each with the kind of value it
/// holds.
enum MirroredSettings {
    static let all: [String: SettingValue.Kind] = [
        AccentSetting.key: .string,
        FileSettings.dateStyleKey: .string,
        FileSettings.use24HourKey: .bool,
        FileSettings.showExtensionsKey: .bool,
        FileSettings.showDetailsKey: .bool,
        FileSettings.relativeModifiedKey: .bool,
        FileSettings.foldersFirstKey: .bool,
        FileSettings.showHiddenKey: .bool,
        FileSettings.confirmExtensionChangesKey: .bool,
        FileSettings.textExtensionsKey: .strings,
        FileSettings.emptyTrashAfterKey: .int,
        FileSettings.undoHistoryKey: .int,
        RecentsSettings.showLastKey: .int,
    ]

    /// Whether the watch takes `value` for `key` from the phone: a mirrored
    /// setting of the right kind and, where the setting limits its values, one
    /// it allows, in the form the watch writes.
    static func accepts(_ value: SettingValue, for key: String) -> Bool {
        guard all[key] == value.kind else { return false }
        switch key {
        case AccentSetting.key:
            return value.string.flatMap(RGBColor.init(displayP3:))?.displayP3 == value.string
        case FileSettings.dateStyleKey:
            return value.string.flatMap(DateStyle.init(rawValue:)) != nil
        case FileSettings.textExtensionsKey:
            return value.strings.map(FileSettings.isWrittenTextExtensions) ?? false
        case FileSettings.emptyTrashAfterKey:
            return value.int.map(FileSettings.emptyTrashAfterChoices.contains) ?? false
        case FileSettings.undoHistoryKey:
            return value.int.map(FileSettings.undoHistoryChoices.contains) ?? false
        case RecentsSettings.showLastKey:
            return value.int.map(RecentsSettings.showLastChoices.contains) ?? false
        default:
            return true
        }
    }
}
