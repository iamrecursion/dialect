import Foundation
import Testing

@testable import Dialect

/// British spelling for wearers whose language is British English and its kin;
/// US English, the source, for everyone else. The system picks the
/// localization; these check what each one holds.
struct LocalizationTests {
    /// Starfire's list. Each needs its own localization: none falls back to
    /// `en-GB` by itself.
    static let british = ["en-GB", "en-AU", "en-NZ", "en-IE", "en-IN"]

    @Test(arguments: british)
    func shipsTheLocalization(_ identifier: String) {
        #expect(Bundle.main.localizations.contains(identifier))
    }

    @Test(arguments: british)
    func spellsItTheBritishWay(_ identifier: String) throws {
        let bundle = try #require(localization(identifier))
        #expect(
            bundle.localizedString(forKey: "Accent Color", value: nil, table: nil)
                == "Accent Colour")
        #expect(
            bundle.localizedString(forKey: "Use a hex color like %@", value: nil, table: nil)
                == "Use a hex colour like %@")
    }

    private func localization(_ identifier: String) -> Bundle? {
        return Bundle.main.path(forResource: identifier, ofType: "lproj").flatMap(
            Bundle.init(path:))
    }
}
