import Foundation

/// How long the bin keeps an item: `days` after it was deleted, or for good
/// when that's `nil`.
enum BinExpiry {
    private static let day: TimeInterval = 24 * 60 * 60

    /// Whole days until the bin empties itself of the item, rounded up so the
    /// last day is 1.
    static func daysLeft(deleted: Date, now: Date, after days: Int?) -> Int? {
        guard let days else { return nil }
        let left = deleted.addingTimeInterval(Double(days) * day).timeIntervalSince(now)
        return max(0, Int((left / day).rounded(.up)))
    }

    /// An item's lines beneath its name: "Deleted *when*", then the days left
    /// when the bin empties itself.
    static func detail(
        deleted: Date, now: Date, relative: Bool, style: DateStyle, use24Hour: Bool,
        emptyAfter days: Int?
    ) -> [String] {
        let when = DateDisplay.string(
            for: deleted, now: now, relative: relative, style: style, use24Hour: use24Hour,
            startsSentence: false)
        let line = String(localized: "Deleted \(when)")
        guard let left = daysLeft(deleted: deleted, now: now, after: days) else { return [line] }
        return [line, daysLeft(left)]
    }

    static func daysLeft(_ days: Int) -> String {
        return days == 1
            ? String(localized: "1 day left") : String(localized: "\(days) days left")
    }

    /// Whether it's been in the bin `days` or more.
    static func isExpired(deleted: Date, now: Date, after days: Int?) -> Bool {
        guard let days else { return false }
        return now >= deleted.addingTimeInterval(Double(days) * day)
    }
}
