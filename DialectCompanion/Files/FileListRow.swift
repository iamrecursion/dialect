import SwiftUI

/// A kind's icon, in the tint.
struct FileListIcon: View {
    let kind: FileKind

    var body: some View {
        kind.symbol.image
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }
}

/// A list row's layout: an icon beside a title and any lines beneath, the text
/// staying clear of the icon at any size.
struct ListRowLabel<Icon: View, Title: View>: View {
    var lines: [String] = []
    @ViewBuilder let icon: Icon
    @ViewBuilder let title: Title

    /// Wide enough for any kind's icon at the default text size.
    @ScaledMetric(relativeTo: .title2) private var iconWidth: CGFloat = 36

    var body: some View {
        HStack(spacing: 12) {
            icon
                .font(.title2)
                .frame(width: iconWidth)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .lineLimit(3)
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }
}

/// An item in a list: its icon, its name, and a line beneath when there's one.
struct FileListRow: View {
    let item: FileItem
    var detail: String?
    let showExtensions: Bool

    var body: some View {
        ListRowLabel(lines: detail.map { [$0] } ?? []) {
            FileListIcon(kind: item.kind)
        } title: {
            Text(verbatim: item.displayName(showExtensions: showExtensions))
                // `Color`s, as a list's button tints hierarchical styles.
                .foregroundStyle(item.isHidden ? Color.secondary : Color.primary)
        }
    }
}

/// Rows shaped like those being read, pulsing until they arrive.
struct LoadingRows: View {
    let showsDetails: Bool

    /// Of differing lengths, like a real folder's names.
    private static let names = [
        "Loading item", "Item", "A longer loading item", "Loading", "Item name",
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ForEach(Array(Self.names.enumerated()), id: \.offset) { index, name in
            ListRowLabel(lines: showsDetails ? ["2026-01-01 00:00 \u{2022} 4 KB"] : []) {
                FileListIcon(kind: .folder)
            } title: {
                Text(verbatim: name)
            }
            .redacted(reason: .placeholder)
            .phaseAnimator(reduceMotion ? [1] : [1, 0.5]) { row, opacity in
                row.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
            .accessibilityHidden(index != 0)
        }
    }
}
