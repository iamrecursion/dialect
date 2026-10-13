import Foundation

/// The `UserDefaults` keys and defaults behind Settings › Files, and Settings ›
/// Appearance's date settings.
enum FileSettings {
    static let showExtensionsKey = "files.showExtensions"
    static let showExtensionsDefault = true

    /// The detail line under each row's name.
    static let showDetailsKey = "files.showDetails"
    static let showDetailsDefault = false

    /// Last Modified: Relative (true) or Date and Time.
    static let relativeModifiedKey = "files.relativeModified"
    static let relativeModifiedDefault = true

    static let foldersFirstKey = "files.foldersFirst"
    static let foldersFirstDefault = true

    static let showHiddenKey = "files.showHidden"
    static let showHiddenDefault = false

    /// The user's text extensions.
    static let textExtensionsKey = "files.textExtensions"

    /// Whether changing a file's extension asks first.
    static let confirmExtensionChangesKey = "files.confirmExtensionChanges"
    static let confirmExtensionChangesDefault = true

    /// Days an item stays in the bin; 0 for Never.
    static let emptyTrashAfterKey = "files.emptyTrashAfter"
    static let emptyTrashAfterDefault = 30
    static let emptyTrashAfterChoices = [0, 1, 3, 7, 14, 30, 90]

    /// Steps the undo history keeps.
    static let undoHistoryKey = "files.undoHistory"
    static let undoHistoryDefault = 20
    static let undoHistoryChoices = [20, 50, 100]

    static let dateStyleKey = "appearance.dates"
    static let dateStyleDefault = DateStyle.system

    static let use24HourKey = "appearance.use24Hour"

    /// Use 24-Hour Time's default: the watch's setting, until the user changes
    /// it here.
    static var use24HourDefault: Bool { uses24Hour(in: .current) }

    /// Whether a locale's preferred time format is 24-hour, including the
    /// user's choice for the current locale.
    static func uses24Hour(in locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)
        return format?.contains(where: { $0 == "H" || $0 == "k" }) ?? false
    }

    /// Typed extensions: lowercase, without the dot, with blanks dropped.
    static func textExtensions(from typed: [String]) -> Set<String> {
        return Set(typed.map(normalizedExtension).filter { !$0.isEmpty })
    }

    /// A typed extension: trimmed, lowercase, and without a leading dot.
    static func normalizedExtension(_ typed: String) -> String {
        var ext = typed.trimmingCharacters(in: .whitespaces).lowercased()
        if ext.hasPrefix(".") { ext.removeFirst() }
        return ext.trimmingCharacters(in: .whitespaces)
    }

    /// Days an item stays in the bin, or `nil` for Never.
    static func emptyTrashAfter(in defaults: UserDefaults = .standard) -> Int? {
        let days =
            defaults.object(forKey: emptyTrashAfterKey) == nil
            ? emptyTrashAfterDefault : defaults.integer(forKey: emptyTrashAfterKey)
        return days > 0 ? days : nil
    }

    /// Empty Trash After's choice as its picker shows it.
    static func emptyTrashAfterTitle(_ days: Int) -> String {
        switch days {
        case 0: return String(localized: "Never")
        case 1: return String(localized: "1 Day")
        default: return String(localized: "\(days) Days")
        }
    }

    static func undoHistory(in defaults: UserDefaults = .standard) -> Int {
        let steps = defaults.integer(forKey: undoHistoryKey)
        return steps > 0 ? steps : undoHistoryDefault
    }

    static func shorteningNote(dropping steps: Int) -> String {
        return steps == 1
            ? String(localized: "The oldest step will be dropped and can't then be undone.")
            : String(
                localized: "The oldest \(steps) steps will be dropped and can't then be undone.")
    }

    /// Text Extensions' list as stored, without blanks.
    static func storedTextExtensions(in defaults: UserDefaults = .standard) -> [String] {
        let typed = defaults.stringArray(forKey: textExtensionsKey) ?? []
        return typed.filter { !normalizedExtension($0).isEmpty }
    }

    /// The user's text extensions, as stored.
    static func textExtensions(in defaults: UserDefaults = .standard) -> Set<String> {
        return textExtensions(from: defaults.stringArray(forKey: textExtensionsKey) ?? [])
    }
}

/// Settings › Appearance › Dates.
enum DateStyle: String, CaseIterable, Sendable {
    /// The watch's date order and separators.
    case system

    /// `2026-10-03 14:05`.
    case iso

    var title: LocalizedStringResource {
        switch self {
        case .system: return "System"
        case .iso: return "ISO"
        }
    }
}
