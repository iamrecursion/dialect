import Foundation
import Testing

@testable import Dialect

/// Which values the watch takes from the phone.
struct MirroredSettingsTests {
    private func accepts(_ value: SettingValue, _ key: String) -> Bool {
        return MirroredSettings.accepts(value, for: key)
    }

    /// Every setting's default is taken.
    @Test func acceptsEveryEffectiveDefault() {
        let store = TestDefaults()
        for (key, value) in EffectiveSettings.read(from: store.defaults) {
            #expect(accepts(value, key), "\(key)")
        }
    }

    @Test func refusesTheWrongKind() {
        #expect(!accepts(.int(1), FileSettings.showHiddenKey))
        #expect(!accepts(.string("20"), FileSettings.undoHistoryKey))
        #expect(!accepts(.string("md"), FileSettings.textExtensionsKey))
    }

    @Test func refusesASettingNotMirrored() {
        #expect(!accepts(.strings(["md"]), FileSettings.recentExtensionsKey))
    }

    @Test func takesOnlyTheChoices() {
        #expect(accepts(.int(50), FileSettings.undoHistoryKey))
        #expect(!accepts(.int(30), FileSettings.undoHistoryKey))
        #expect(accepts(.int(0), FileSettings.emptyTrashAfterKey))
        #expect(!accepts(.int(2), FileSettings.emptyTrashAfterKey))
        #expect(accepts(.int(20), RecentsSettings.showLastKey))
        #expect(!accepts(.int(0), RecentsSettings.showLastKey))
        #expect(accepts(.string("iso"), FileSettings.dateStyleKey))
        #expect(!accepts(.string("ISO"), FileSettings.dateStyleKey))
    }

    /// The accent as the watch writes it, in Display P3. An old hex value is
    /// refused.
    @Test func takesOnlyADisplayP3Color() {
        #expect(accepts(.string(RGBColor.dialectGreen.displayP3), AccentSetting.key))
        #expect(!accepts(.string("color(display-p3 0.5 0.25 1)"), AccentSetting.key))
        #expect(!accepts(.string("#81C977"), AccentSetting.key))
        #expect(!accepts(.string("green"), AccentSetting.key))
    }

    @Test(arguments: [[], ["md"], ["el", "rkt"], ["png"]])
    func takesTextExtensionsInWrittenForm(_ list: [String]) {
        #expect(accepts(.strings(list), FileSettings.textExtensionsKey))
    }

    @Test(arguments: [["MD"], [".el"], [" el"], [""], ["a/b"], ["tar.gz"], ["el", "el"]])
    func refusesTextExtensionsInAnyOtherForm(_ list: [String]) {
        #expect(!accepts(.strings(list), FileSettings.textExtensionsKey))
    }
}
