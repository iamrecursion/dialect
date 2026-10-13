import Foundation
import Testing

@testable import Dialect

/// What the watch sends: the settings as its screens read them.
struct EffectiveSettingsTests {
    private static let british = Locale(identifier: "en_GB")
    private static let american = Locale(identifier: "en_US")

    @Test func readsEveryMirroredSettingByItsKind() {
        let read = EffectiveSettings.read(from: TestDefaults().defaults)
        #expect(Set(read.keys) == Set(MirroredSettings.all.keys))
        for (key, value) in read {
            #expect(value.kind == MirroredSettings.all[key], "\(key)")
        }
    }

    @Test func appliesTheDefaults() {
        let read = EffectiveSettings.read(from: TestDefaults().defaults, locale: Self.british)
        #expect(read[AccentSetting.key] == .string(RGBColor.dialectGreen.displayP3))
        #expect(read[FileSettings.dateStyleKey] == .string("system"))
        #expect(read[FileSettings.use24HourKey] == .bool(true))
        #expect(read[FileSettings.showExtensionsKey] == .bool(true))
        #expect(read[FileSettings.showDetailsKey] == .bool(false))
        #expect(read[FileSettings.relativeModifiedKey] == .bool(true))
        #expect(read[FileSettings.foldersFirstKey] == .bool(true))
        #expect(read[FileSettings.showHiddenKey] == .bool(false))
        #expect(read[FileSettings.confirmExtensionChangesKey] == .bool(true))
        #expect(read[FileSettings.textExtensionsKey] == .strings([]))
        #expect(read[FileSettings.emptyTrashAfterKey] == .int(30))
        #expect(read[FileSettings.undoHistoryKey] == .int(20))
        #expect(read[RecentsSettings.showLastKey] == .int(5))
    }

    /// Use 24-Hour Time defaults to the time format of the watch's locale.
    @Test func defaults24HourTimeFromTheLocale() {
        let store = TestDefaults()
        #expect(
            EffectiveSettings.read(from: store.defaults, locale: Self.american)[
                FileSettings.use24HourKey] == .bool(false))
        store.defaults.set(true, forKey: FileSettings.use24HourKey)
        #expect(
            EffectiveSettings.read(from: store.defaults, locale: Self.american)[
                FileSettings.use24HourKey] == .bool(true))
    }

    @Test func readsWhatsSet() {
        let store = TestDefaults()
        store.defaults.set(true, forKey: FileSettings.showHiddenKey)
        store.defaults.set("iso", forKey: FileSettings.dateStyleKey)
        store.defaults.set(100, forKey: FileSettings.undoHistoryKey)
        store.defaults.set(10, forKey: RecentsSettings.showLastKey)
        let read = EffectiveSettings.read(from: store.defaults)
        #expect(read[FileSettings.showHiddenKey] == .bool(true))
        #expect(read[FileSettings.dateStyleKey] == .string("iso"))
        #expect(read[FileSettings.undoHistoryKey] == .int(100))
        #expect(read[RecentsSettings.showLastKey] == .int(10))
    }

    /// An older setting, in sRGB hex, is sent as Display P3, as the watch reads
    /// it.
    @Test func sendsAnOlderHexAccentAsDisplayP3() {
        let store = TestDefaults()
        store.defaults.set("#63E6E2", forKey: AccentSetting.key)
        #expect(
            EffectiveSettings.read(from: store.defaults)[AccentSetting.key]
                == .string(RGBColor(sRGBRed: 0x63, green: 0xE6, blue: 0xE2).displayP3))
    }

    @Test func sendsNeverAsZero() {
        let store = TestDefaults()
        store.defaults.set(0, forKey: FileSettings.emptyTrashAfterKey)
        #expect(
            EffectiveSettings.read(from: store.defaults)[FileSettings.emptyTrashAfterKey] == .int(0)
        )
    }

    @Test func leavesOutBlankExtensions() {
        let store = TestDefaults()
        store.defaults.set(["fnl", " ", "", ".lisp"], forKey: FileSettings.textExtensionsKey)
        #expect(
            EffectiveSettings.read(from: store.defaults)[FileSettings.textExtensionsKey]
                == .strings(["fnl", ".lisp"]))
    }

    @Test func readsAnUnknownDateStyleAsTheDefault() {
        let store = TestDefaults()
        store.defaults.set("julian", forKey: FileSettings.dateStyleKey)
        #expect(
            EffectiveSettings.read(from: store.defaults)[FileSettings.dateStyleKey]
                == .string("system"))
    }
}
