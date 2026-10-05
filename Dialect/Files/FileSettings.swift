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

    /// The extensions used to make files, most recent first, without dots;
    /// empty for None.
    static let recentExtensionsKey = "files.recentExtensions"

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
        return ext
    }

    /// Why Text Extensions can't add `typed`, or `nil` if it can.
    static func textExtensionProblem(_ typed: String, existing: [String])
        -> TextExtensionProblem?
    {
        let ext = normalizedExtension(typed)
        if ext.isEmpty { return .empty }
        if ext.contains("/") { return .slash }
        if ext.contains(".") { return .dot }
        if textExtensions(from: existing).contains(ext) { return .listed(ext) }
        if let kind = FileKind.classify(name: "x.\(ext)", isDirectory: false, textExtensions: []) {
            return .known(ext, kind)
        }
        return nil
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

    static func recentExtensions(in defaults: UserDefaults = .standard) -> [String] {
        return defaults.stringArray(forKey: recentExtensionsKey) ?? []
    }

    /// Notes that a file was made with `ext`, which Add › File then offers
    /// first.
    static func recordExtension(_ ext: String, in defaults: UserDefaults = .standard) {
        let listed = NameRules.listedExtensions(
            textExtensions: defaults.stringArray(forKey: textExtensionsKey) ?? [])
        defaults.set(
            NameRules.recording(ext, in: recentExtensions(in: defaults), listed: listed),
            forKey: recentExtensionsKey)
    }

    /// The user's text extensions, as stored.
    static func textExtensions(in defaults: UserDefaults = .standard) -> Set<String> {
        return textExtensions(from: defaults.stringArray(forKey: textExtensionsKey) ?? [])
    }
}

/// Why Text Extensions refuses an extension, shown beneath its field.
enum TextExtensionProblem: Equatable, Sendable {
    case empty
    case slash

    /// An extension is the part after the last dot, so it can't hold one.
    case dot
    case listed(String)

    /// Files already gives files with it a kind.
    case known(String, FileKind)

    var reason: String {
        switch self {
        case .empty: return String(localized: "An extension can't be empty.")
        case .slash: return String(localized: "An extension can't contain “/”.")
        case .dot: return String(localized: "An extension can't contain a dot.")
        case .listed(let ext): return String(localized: ".\(ext) is already in the list.")
        case .known(let ext, let kind):
            switch kind {
            case .scheme: return String(localized: "Files already treats .\(ext) as Scheme source.")
            case .image: return String(localized: "Files already treats .\(ext) as an image.")
            case .video: return String(localized: "Files already treats .\(ext) as a video.")
            default: return String(localized: "Files already treats .\(ext) as text.")
            }
        }
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
