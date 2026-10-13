import Foundation

/// The mirrored settings as the watch's screens read them, defaults applied.
enum EffectiveSettings {
    static func read(from defaults: UserDefaults, locale: Locale = .current) -> [String:
        SettingValue]
    {
        func bool(_ key: String, _ fallback: Bool) -> SettingValue {
            return .bool(
                defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key))
        }
        let accent = AccentSetting.color(from: defaults.string(forKey: AccentSetting.key) ?? "")
        let dates =
            defaults.string(forKey: FileSettings.dateStyleKey).flatMap(DateStyle.init)
            ?? FileSettings.dateStyleDefault
        return [
            AccentSetting.key: .string(accent.displayP3),
            FileSettings.dateStyleKey: .string(dates.rawValue),
            FileSettings.use24HourKey: bool(
                FileSettings.use24HourKey, FileSettings.uses24Hour(in: locale)),
            FileSettings.showExtensionsKey: bool(
                FileSettings.showExtensionsKey, FileSettings.showExtensionsDefault),
            FileSettings.showDetailsKey: bool(
                FileSettings.showDetailsKey, FileSettings.showDetailsDefault),
            FileSettings.relativeModifiedKey: bool(
                FileSettings.relativeModifiedKey, FileSettings.relativeModifiedDefault),
            FileSettings.foldersFirstKey: bool(
                FileSettings.foldersFirstKey, FileSettings.foldersFirstDefault),
            FileSettings.showHiddenKey: bool(
                FileSettings.showHiddenKey, FileSettings.showHiddenDefault),
            FileSettings.confirmExtensionChangesKey: bool(
                FileSettings.confirmExtensionChangesKey,
                FileSettings.confirmExtensionChangesDefault),
            FileSettings.textExtensionsKey: .strings(
                FileSettings.storedTextExtensions(in: defaults)),
            FileSettings.emptyTrashAfterKey: .int(FileSettings.emptyTrashAfter(in: defaults) ?? 0),
            FileSettings.undoHistoryKey: .int(FileSettings.undoHistory(in: defaults)),
            RecentsSettings.showLastKey: .int(RecentsSettings.showLast(in: defaults)),
        ]
    }
}
