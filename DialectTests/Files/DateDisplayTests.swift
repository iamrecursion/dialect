import Foundation
import Testing

@testable import Dialect

/// Dates as rows and Info show them: relative, or as Settings › Appearance
/// says.
struct DateDisplayTests {
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-10-03 14:05 UTC.
    private let date = Date(timeIntervalSince1970: 1_791_036_300)
    private let us = Locale(identifier: "en_US")
    private let gb = Locale(identifier: "en_GB")

    private func absolute(_ style: DateStyle, _ use24Hour: Bool, _ locale: Locale) -> String {
        return DateDisplay.string(
            for: date, now: date + 86400 * 400, relative: false, style: style,
            use24Hour: use24Hour, locale: locale, timeZone: utc)
    }

    @Test func iso() {
        #expect(absolute(.iso, true, us) == "2026-10-03 14:05")
        #expect(absolute(.iso, false, us) == "2026-10-03 2:05 PM")
        #expect(absolute(.iso, true, gb) == "2026-10-03 14:05")
        #expect(absolute(.iso, false, gb) == "2026-10-03 2:05 PM")
    }

    @Test func isoPadsMidnight() {
        let midnight = Date(timeIntervalSince1970: 1_790_985_600 + 5 * 60)
        #expect(
            DateDisplay.string(
                for: midnight, now: midnight, relative: false, style: .iso, use24Hour: true,
                locale: us, timeZone: utc) == "2026-10-03 00:05")
        #expect(
            DateDisplay.string(
                for: midnight, now: midnight, relative: false, style: .iso, use24Hour: false,
                locale: us, timeZone: utc) == "2026-10-03 12:05 AM")
    }

    /// The locale's date order, with the hour cycle forced either way.
    @Test func systemFollowsTheLocaleWithTheChosenHourCycle() {
        let us24 = absolute(.system, true, us)
        #expect(us24.contains("10/3/2026"), "\(us24)")
        #expect(us24.contains("14:05"), "\(us24)")
        #expect(!us24.localizedCaseInsensitiveContains("pm"), "\(us24)")

        let us12 = absolute(.system, false, us)
        #expect(us12.contains("2:05"), "\(us12)")
        #expect(us12.localizedCaseInsensitiveContains("pm"), "\(us12)")

        let gb24 = absolute(.system, true, gb)
        #expect(gb24.contains("03/10/2026"), "\(gb24)")
        #expect(gb24.contains("14:05"), "\(gb24)")

        let gb12 = absolute(.system, false, gb)
        #expect(gb12.contains("2:05"), "\(gb12)")
        #expect(gb12.localizedCaseInsensitiveContains("pm"), "\(gb12)")
    }

    @Test func relative() {
        let minutes = DateDisplay.string(
            for: date - 5 * 60, now: date, relative: true, style: .iso, use24Hour: true,
            locale: us, timeZone: utc)
        #expect(minutes == "5 minutes ago")
        #expect(minutes.contains("ago"), "\(minutes)")

        let yesterday = DateDisplay.string(
            for: date - 86400, now: date, relative: true, style: .iso, use24Hour: true,
            locale: gb, timeZone: utc)
        #expect(yesterday == "Yesterday")

        let lastMonth = DateDisplay.string(
            for: date - 40 * 86400, now: date, relative: true, style: .iso, use24Hour: true,
            locale: us, timeZone: utc)
        #expect(lastMonth == "Last month")
    }

    @Test func the24HourDefaultFollowsTheLocale() {
        #expect(FileSettings.uses24Hour(in: Locale(identifier: "en_US")) == false)
        #expect(FileSettings.uses24Hour(in: Locale(identifier: "en_GB")) == true)
        #expect(FileSettings.uses24Hour(in: Locale(identifier: "de_DE")) == true)
        #expect(FileSettings.uses24Hour(in: Locale(identifier: "en_US@hours=h23")) == true)
    }

    @Test func sizes() {
        #expect(SizeDisplay.string(nil) == "—")
        #expect(SizeDisplay.string(0) == "Zero KB")
        #expect(SizeDisplay.string(1234) == "1 KB")
    }

    /// Typed extensions are matched lowercase, without the dot.
    @Test func normalizesTextExtensions() {
        #expect(
            FileSettings.textExtensions(from: [".EL", "rkt", " lua ", "", "."]) == [
                "el", "rkt", "lua",
            ])
    }
}
