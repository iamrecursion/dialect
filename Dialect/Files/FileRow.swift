import SwiftUI
import WatchKit

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

/// One item in a folder: its icon, its name, and its details when shown. A tap
/// opens it; a long press, or VoiceOver's More action, opens its More screen.
/// Swiping left offers Delete and More, and swiping right Copy and Select, each
/// taking a tap, as watchOS lists have no full swipe.
///
/// In select mode the row shows a selection circle and its details, has no
/// swipes or long press, and a tap calls `open`, which toggles selection.
///
/// `open` must ignore the tap that ends a long press; the folder does, as More
/// is on top by then.
struct FileRow: View {
    let item: FileItem
    let size: Int64?
    let style: FileRowStyle

    /// Whether it's selected, in select mode; `nil` outside it.
    var isSelected: Bool?

    /// Show in Files' highlight, in place of the row's platter.
    var highlight: Color?
    let open: () -> Void
    let more: () -> Void
    let delete: () -> Void
    let copy: () -> Void
    let select: () -> Void

    /// As `MenuRowLabel`'s, so names line up with the menus'.
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 30
    @Environment(\.dialectAccent) private var accent

    private var name: String { item.displayName(showExtensions: style.showExtensions) }

    private var showsDetails: Bool { style.showDetails || isSelected != nil }

    var body: some View {
        content
            .listItemTint(highlight)
    }

    @ViewBuilder private var content: some View {
        if let isSelected {
            label(isSelected: isSelected)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            label(isSelected: nil)
                // Simultaneous, as `onLongPressGesture` on a button swallows its taps on watchOS
                // 27. The button's action still follows when the finger lifts; `open` ignores it
                // once More is showing.
                .simultaneousGesture(LongPressGesture().onEnded { _ in more() })
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive, action: delete) {
                        Label("Delete", systemImage: "trash")
                    }
                    Button(action: more) {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .tint(.gray)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button(action: copy) {
                        Label("Copy", systemImage: ClipboardSymbol.copy)
                    }
                    .tint(accent)
                    Button(action: select) {
                        Label("Select", systemImage: SelectSymbol.select)
                    }
                    .tint(.gray)
                }
                .accessibilityAction(named: Text("Delete"), delete)
                .accessibilityAction(named: Text("More"), more)
                .accessibilityAction(named: Text("Copy"), copy)
                .accessibilityAction(named: Text("Select"), select)
        }
    }

    private func label(isSelected: Bool?) -> some View {
        return Button(action: open) {
            HStack(spacing: 10) {
                RowIcon(kind: item.kind, isSelected: isSelected, width: iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if showsDetails {
                        Text(verbatim: style.detail(for: item, size: size))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: accessibilityValue))
    }

    /// The kind, then the details when they're shown.
    private var accessibilityValue: String {
        let kind = String(localized: item.kind.typeName)
        return showsDetails ? "\(kind), \(style.detail(for: item, size: size))" : kind
    }
}

/// A row's icon with select mode's circle before it, or in its place where the
/// screen is narrow to fit both.
struct RowIcon: View {
    let kind: FileKind

    /// Whether it's selected, in select mode; `nil` outside it.
    let isSelected: Bool?

    /// The icon's slot, as `MenuRowLabel`'s.
    let width: CGFloat

    /// Whether the circle takes the icon's place.
    nonisolated static func circleReplacesIcon(screenWidth: CGFloat, iconWidth: CGFloat) -> Bool {
        return screenWidth < 6.5 * iconWidth
    }

    var body: some View {
        if let isSelected {
            if Self.circleReplacesIcon(
                screenWidth: WKInterfaceDevice.current().screenBounds.width, iconWidth: width)
            {
                SelectionCircle(isSelected: isSelected)
                    .frame(width: width)
            } else {
                SelectionCircle(isSelected: isSelected)
                icon
            }
        } else {
            icon
        }
    }

    private var icon: some View {
        return FileIcon(kind: kind)
            .font(.title3)
            .frame(width: width)
    }
}

/// A row's circle in select mode, filled with a check in the accent once
/// selected.
struct SelectionCircle: View {
    let isSelected: Bool

    @Environment(\.dialectAccent) private var accent

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? accent : .secondary)
            .accessibilityHidden(true)
    }
}

/// Show in Files' highlight: the row's platter blended toward the accent. It's
/// a list item tint, animated by hand.
enum RowHighlight {
    /// How far toward the accent a fully lit row goes.
    static let strength: Float = 0.45

    /// The platter a list row's button draws: (34, 34, 35).
    static let platter = Color.Resolved(
        colorSpace: .sRGB, red: 34 / 255, green: 34 / 255, blue: 35 / 255)

    /// Blended in sRGB by hand, as `Color.mix`'s colors weren't redrawn as they
    /// changed.
    static func color(accent: Color.Resolved, amount: Double) -> Color.Resolved {
        let t = strength * Float(amount)
        func blend(_ from: Float, _ to: Float) -> Float { from + (to - from) * t }
        return Color.Resolved(
            colorSpace: .sRGB, red: blend(platter.red, accent.red),
            green: blend(platter.green, accent.green), blue: blend(platter.blue, accent.blue))
    }
}
