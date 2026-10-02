import SwiftUI

/// A list whose first row is a bar of two or three icon buttons, drawn exactly
/// like the list's rows with the same color, corners, and gap.
///
/// The buttons are bordered `Button`s, rather than navigation links as a link
/// inside a list ignores its button style and draws as bare text. Each is its
/// own tap target with the system's press animation, while what a tap does is
/// up to `perform`.
struct ActionList<Rows: View>: View {
    let actions: [MenuItem]

    /// The buttons' height in points at the default text size, scaled with the
    /// text size. `nil` makes them exactly a list row's height. A height below
    /// a row's leaves space around them, since the list keeps its minimum row
    /// height.
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
                        // The icon is an overlay so that it does not set the button's height, which
                        // would outgrow a list row's: the button fills the row instead, and the
                        // icon is drawn centered on it.
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay {
                                Image(systemName: item.systemImage)
                                    .font(.title3)
                                    .imageScale(.large)
                                    .foregroundStyle(accent)
                                    .offset(y: item.opticalOffset * point)
                            }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .tint(Self.rowGray)
                    // Icon only, so VoiceOver needs the title.
                    .accessibilityLabel(Text(item.title))
                }
            }
            .frame(height: actionHeight.map { $0 * point })
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            rows
        }
    }
}
