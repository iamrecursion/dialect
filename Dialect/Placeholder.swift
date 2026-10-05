import SwiftUI

/// A destination that is not built yet: its name, centered, and as its title.
struct Placeholder: View {
    let title: Text

    init(title: LocalizedStringResource) {
        self.title = Text(title)
    }

    /// For a title that isn't translated, such as a file's name.
    init(verbatim title: String) {
        self.title = Text(verbatim: title)
    }

    var body: some View {
        title
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
    }
}

#Preview {
    Placeholder(title: "Files")
}
