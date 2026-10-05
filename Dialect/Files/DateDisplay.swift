import Foundation

/// Modified and Created as shown by the item rows and info screen.
enum DateDisplay {
    /// `startsSentence` capitalizes a relative date: "Yesterday", or "Deleted
    /// yesterday" without it.
    static func string(
        for date: Date, now: Date, relative: Bool, style: DateStyle, use24Hour: Bool,
        startsSentence: Bool = true, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String {
        if relative {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.dateTimeStyle = .named

            // "Last month": the short and abbreviated styles give "Last mo.".
            formatter.unitsStyle = .full

            formatter.formattingContext = startsSentence ? .beginningOfSentence : .middleOfSentence

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            formatter.calendar = calendar
            return formatter.localizedString(for: date, relativeTo: now)
        }
        switch style {
        case .system:
            var components = Locale.Components(locale: locale)
            components.hourCycle = use24Hour ? .zeroToTwentyThree : .oneToTwelve
            var format = Date.FormatStyle(date: .numeric, time: .shortened)
            format.locale = Locale(components: components)
            format.timeZone = timeZone
            return date.formatted(format)
        case .iso:
            return iso(date, use24Hour: use24Hour, timeZone: timeZone)
        }
    }

    /// `2026-10-03 14:05`, or `2026-10-03 2:05 PM` in 12-hour time, in any
    /// language.
    private static func iso(_ date: Date, use24Hour: Bool, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let (year, month, day) = (parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let (hour, minute) = (parts.hour ?? 0, parts.minute ?? 0)
        let day4 = "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
        if use24Hour {
            return "\(day4) \(pad(hour, 2)):\(pad(minute, 2))"
        }
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(day4) \(hour12):\(pad(minute, 2)) \(hour < 12 ? "AM" : "PM")"
    }

    private static func pad(_ number: Int, _ width: Int) -> String {
        let digits = String(number)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
