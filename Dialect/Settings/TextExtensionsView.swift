import SwiftUI

/// Settings › Files › Text Extensions, containing the user's custom extensions
/// for text files.
struct TextExtensionsView: View {
    @State private var extensions: [String] = []
    @State private var typed = ""
    @State private var problem: TextExtensionProblem?

    var body: some View {
        List {
            Section {
                TextField("Add Extension", text: $typed)
                    .onSubmit(add)
                    .onChange(of: typed) { problem = nil }
                if let problem {
                    Text(problem.reason)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            Section {
                ForEach(extensions, id: \.self) { ext in
                    Text(verbatim: ".\(FileSettings.normalizedExtension(ext))")
                }
                .onDelete { offsets in
                    extensions.remove(atOffsets: offsets)
                    save()
                }
            } footer: {
                Text("Files with these extensions are treated as text.")
            }
        }
        .navigationTitle("Text Extensions")
        .onAppear { extensions = FileSettings.storedTextExtensions() }
        // The phone can change the list while it's shown.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) {
            _ in
            let stored = FileSettings.storedTextExtensions()
            if stored != extensions { extensions = stored }
        }
    }

    /// Adds what was typed, or says why it can't.
    private func add() {
        guard !typed.isEmpty else { return }
        if let refused = FileSettings.textExtensionProblem(typed, existing: extensions) {
            problem = refused
            return
        }
        extensions.append(FileSettings.normalizedExtension(typed))
        typed = ""
        save()
    }

    private func save() {
        UserDefaults.standard.set(extensions, forKey: FileSettings.textExtensionsKey)
    }
}

#Preview {
    NavigationStack {
        TextExtensionsView()
    }
}
