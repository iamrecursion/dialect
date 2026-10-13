import Foundation

// Watch only: the recent extensions need `NameRules`.
extension FileSettings {
    /// The extensions used to make files, most recent first, without dots;
    /// empty for None.
    static let recentExtensionsKey = "files.recentExtensions"

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
}
