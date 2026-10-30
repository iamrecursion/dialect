import SwiftUI

/// How long ago a screen's listing was seen, in steps that can be read at a
/// glance: seconds, each of the first five minutes, 10, 20 and 30 minutes, then
/// hours, days and weeks.
enum LastSeen {
    private static let minuteSteps = [1, 2, 3, 4, 5, 10, 20, 30]
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 60 * 60
    private static let day: TimeInterval = 24 * 60 * 60
    private static let week: TimeInterval = 7 * 24 * 60 * 60

    /// The step `elapsed` falls in, in seconds; zero under a minute.
    static func step(for elapsed: TimeInterval) -> TimeInterval {
        if elapsed < hour {
            let minutes = Int(elapsed / minute)
            return TimeInterval(minuteSteps.last { $0 <= minutes } ?? 0) * minute
        }
        let unit = elapsed < day ? hour : elapsed < week ? day : week
        return (elapsed / unit).rounded(.down) * unit
    }

    /// "seconds ago", "5 minutes ago", "2 hours ago".
    static func phrase(for elapsed: TimeInterval, locale: Locale = .current) -> String {
        let step = step(for: elapsed)
        guard step > 0 else { return String(localized: "seconds ago") }
        // In the step's own unit, as the formatter's choice of unit for an interval rounds unevenly
        // ("1 week ago" at 14 days).
        var components = DateComponents()
        if step < hour {
            components.minute = -Int(step / minute)
        } else if step < day {
            components.hour = -Int(step / hour)
        } else if step < week {
            components.day = -Int(step / day)
        } else {
            components.weekOfMonth = -Int(step / week)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.formattingContext = .middleOfSentence
        return formatter.localizedString(from: components)
    }

    /// Each time the phrase changes, for four weeks after `seen`.
    static func changes(after seen: Date) -> [Date] {
        let minutes = (minuteSteps + [60]).map { TimeInterval($0) * minute }
        let hours = (2..<24).map { TimeInterval($0) * hour }
        let days = (1..<7).map { TimeInterval($0) * day }
        let weeks = (1...4).map { TimeInterval($0) * week }
        return (minutes + hours + days + weeks).map { seen.addingTimeInterval($0) }
    }
}

extension View {
    /// The screen's "last seen" under its title, kept current as it ages.
    func lastSeenSubtitle(_ state: BrowsingState, of seen: BrowsingState.Seen) -> some View {
        return modifier(LastSeenSubtitle(state: state, seen: seen))
    }
}

/// Wakes when the phrase next changes.
private struct LastSeenSubtitle: ViewModifier {
    let state: BrowsingState
    let seen: BrowsingState.Seen

    @State private var now = Date()

    private var nextChange: Date? {
        guard case .cached(let date) = state else { return nil }
        return LastSeen.changes(after: date).first { $0 > now }
    }

    func body(content: Content) -> some View {
        content
            .navigationSubtitle(state.subtitle(of: seen, now: now))
            .onChange(of: state) { now = Date() }
            .task(id: nextChange) {
                guard let nextChange else { return }
                try? await Task.sleep(for: .seconds(max(0, nextChange.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                now = Date()
            }
    }
}
