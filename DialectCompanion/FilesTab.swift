import SwiftUI

/// The watch's files.
struct FilesTab: View {
    var body: some View {
        NavigationStack {
            PlaceholderScreen(title: "Files")
        }
    }
}

/// A screen not built yet: "Coming later", under its title.
struct PlaceholderScreen: View {
    let title: LocalizedStringResource

    var body: some View {
        Text("Coming later")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text(title))
    }
}

#Preview {
    FilesTab()
}
