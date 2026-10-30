import Foundation

/// The settings shaping a folder's rows, read once for all of them.
struct FileRowStyle {
    var showExtensions: Bool
    var showDetails: Bool
    var relativeModified: Bool
    var dateStyle: DateStyle
    var use24Hour: Bool

    /// What relative dates count back from.
    var now: Date
    var timeZone: TimeZone = .current

    /// The detail line: "*Modified* ∘ *Size*", with "—" for anything unknown,
    /// such as a folder's size before it's worked out.
    func detail(for item: FileItem, size: Int64?) -> String {
        let modified =
            item.modified.map {
                DateDisplay.string(
                    for: $0, now: now, relative: relativeModified, style: dateStyle,
                    use24Hour: use24Hour, timeZone: timeZone)
            } ?? "—"
        return "\(modified) ∘ \(SizeDisplay.string(size))"
    }
}
