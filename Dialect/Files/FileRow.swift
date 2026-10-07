import SwiftUI

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
/// Swiping left offers Delete and More, and swiping right Copy, each taking a
/// tap, as watchOS lists have no full swipe.
///
/// `open` must ignore the tap that ends a long press; the folder does, as More
/// is on top by then.
struct FileRow: View {
    let item: FileItem
    let size: Int64?
    let style: FileRowStyle
    let open: () -> Void
    let more: () -> Void
    let delete: () -> Void
    let copy: () -> Void

    /// As `MenuRowLabel`'s, so names line up with the menus'.
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 30
    @Environment(\.dialectAccent) private var accent

    private var name: String { item.displayName(showExtensions: style.showExtensions) }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                FileIcon(kind: item.kind)
                    .font(.title3)
                    .frame(width: iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if style.showDetails {
                        Text(verbatim: style.detail(for: item, size: size))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        // Simultaneous, as `onLongPressGesture` on a button swallows its taps on watchOS 27. The
        // button's action still follows when the finger lifts; `open` ignores it once More is
        // showing.
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
        }
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityAction(named: Text("Delete"), delete)
        .accessibilityAction(named: Text("More"), more)
        .accessibilityAction(named: Text("Copy"), copy)
    }

    /// The kind, then the details when they're shown.
    private var accessibilityValue: String {
        let kind = String(localized: item.kind.typeName)
        return style.showDetails ? "\(kind), \(style.detail(for: item, size: size))" : kind
    }
}
