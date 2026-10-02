import SwiftUI

/// The app's root.
struct MainMenu: View {
    static let topRow = [
        // The pencil's tip sticks up above the square, which then sits low beside its neighbors, so
        // we have to offset it.
        MenuItem(
            title: "New REPL", systemImage: "square.and.pencil", route: .newREPL,
            opticalOffset: -2.25),
        MenuItem(title: "Resume Session", systemImage: "playpause", route: .resumeSession),
        MenuItem(
            title: "Sessions",
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            route: .sessions),
    ]

    static let rows = [
        MenuItem(title: "Files", systemImage: "folder", route: .files),
        MenuItem(title: "Downloader", systemImage: "arrow.down.circle", route: .downloader),
        MenuItem(title: "Settings", systemImage: "gear", route: .settings),
    ]

    /// The navigation stack's path, which the top row's buttons push onto.
    @Binding var path: [Route]

    var body: some View {
        ActionList(actions: Self.topRow, perform: { path.append($0.route) }) {
            ForEach(Self.rows) { item in
                NavigationLink(value: item.route) {
                    MenuRowLabel(item: item)
                }
            }
        }
        .navigationTitle("Dialect")
    }
}

#Preview {
    NavigationStack {
        MainMenu(path: .constant([]))
    }
}
