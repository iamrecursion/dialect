import SwiftUI

/// A list whose first row is a bar of two or three icon buttons, drawn exactly
/// like the list's rows with the same color, corners, and gap.
///
/// The buttons are bordered `Button`s: a navigation link inside a list ignores
/// its button style and draws as bare text. Each is a separate tap target with
/// the system's press animation; `perform` decides what a tap does.
struct ActionList<Rows: View>: View {
    let actions: [MenuItem]

    /// The buttons' height in points at the default text size, scaled with the
    /// text size. `nil` makes them a list row's height. A height below a row's
    /// leaves space around them, as the list keeps its minimum row height.
    var actionHeight: CGFloat?
    let perform: (MenuItem) -> Void
    @ViewBuilder var rows: Rows

    @Environment(\.dialectAccent) private var accent

    /// One point at the default text size, scaled with the buttons' icons.
    @ScaledMetric(relativeTo: .title3) private var point: CGFloat = 1

    /// Measured on watchOS 27: list rows sit 5 pt apart.
    private static var spacing: CGFloat { 5 }

    /// The tint that makes a bordered button's fill the list rows' gray, (34,
    /// 34, 35). There is no API for that gray; the button draws its tint at
    /// reduced strength, and this value lands on it exactly for watchOS 27.
    private static var rowGray: Color { Color(red: 0.54, green: 0.54, blue: 0.55) }

    var body: some View {
        List {
            HStack(spacing: Self.spacing) {
                ForEach(actions) { item in
                    Button {
                        perform(item)
                    } label: {
                        // An overlay, so the icon doesn't set the button's height, which would
                        // outgrow a row's: the button fills the row and the icon is centered on it.
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay {
                                HStack(spacing: 3 * point) {
                                    Image(systemName: item.systemImage)
                                        .imageScale(.large)
                                        .offset(y: item.opticalOffset * point)
                                    if let count = item.count {
                                        Text(count, format: .number)
                                            .font(.body.weight(.semibold))
                                            .monospacedDigit()
                                            .fixedSize()
                                    }
                                }
                                .font(.title3)
                                .foregroundStyle(accent)
                                // The button dims its fill, but not an icon with a set color.
                                .opacity(item.isDisabled ? 0.4 : 1)
                                // The button's label and value say it all.
                                .accessibilityHidden(true)
                            }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .tint(Self.rowGray)
                    .disabled(item.isDisabled)
                    // Icon only, so VoiceOver needs the title.
                    .accessibilityLabel(Text(item.title))
                    .accessibilityValue(Text(verbatim: item.countDescription ?? ""))
                }
            }
            .frame(height: actionHeight.map { $0 * point })
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            rows
        }
    }
}
