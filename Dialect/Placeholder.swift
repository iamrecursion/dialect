import SwiftUI

/// A destination that is not built yet: its name, centered, and as its title.
struct Placeholder: View {
    let title: LocalizedStringResource

    var body: some View {
        Text(title)
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text(title))
    }
}

#Preview {
    Placeholder(title: "Files")
}
