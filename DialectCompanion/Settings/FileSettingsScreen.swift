import SwiftUI

/// The watch's Settings › Files, in its groups and order.
struct FileSettingsScreen: View {
    @Environment(PhoneLink.self) private var link

    /// A shorter Undo History that would drop steps, waiting for its
    /// confirmation.
    @State private var shortening: (steps: Int, dropping: Int)?

    var body: some View {
        List {
            SettingToggle(title: "File Extensions", key: FileSettings.showExtensionsKey)
            SettingToggle(title: "Details", key: FileSettings.showDetailsKey)
            SettingPicker(
                title: "Modified", key: FileSettings.relativeModifiedKey, choices: [true, false]
            ) { $0 ? Text("Relative") : Text("Date and Time") }
            SettingToggle(title: "Folders First", key: FileSettings.foldersFirstKey)
            SettingToggle(title: "Hidden Files", key: FileSettings.showHiddenKey)

            Section {
                SettingToggle(
                    title: "Confirm Extension Changes", key: FileSettings.confirmExtensionChangesKey
                )
                if let extensions = link.value(FileSettings.textExtensionsKey)?.strings {
                    NavigationLink {
                        TextExtensionsScreen()
                    } label: {
                        LabeledContent {
                            Text(extensions.count.formatted())
                        } label: {
                            SettingTitle(
                                title: "Text Extensions", key: FileSettings.textExtensionsKey)
                        }
                    }
                }
            }

            Section {
                SettingPicker(
                    title: "Empty Trash After", key: FileSettings.emptyTrashAfterKey,
                    choices: FileSettings.emptyTrashAfterChoices
                ) { Text(FileSettings.emptyTrashAfterTitle($0)) }
                SettingPicker(
                    title: "Undo History", key: FileSettings.undoHistoryKey,
                    choices: FileSettings.undoHistoryChoices, choose: chooseUndoHistory
                ) { Text("\($0) Steps") }
            }
        }
        .navigationTitle("Files")
        .alert(
            "Shorten Undo History?",
            isPresented: Binding(
                get: { shortening != nil }, set: { if !$0 { shortening = nil } }),
            presenting: shortening
        ) { shortening in
            Button("Shorten", role: .destructive) {
                link.edit(FileSettings.undoHistoryKey, to: .int(shortening.steps))
            }
            Button("Cancel", role: .cancel) {}
        } message: { shortening in
            Text(FileSettings.shorteningNote(dropping: shortening.dropping))
        }
    }

    /// Sets Undo History, first asking, as the watch does, when a shorter one
    /// would drop steps.
    private func chooseUndoHistory(_ steps: Int) {
        guard steps != link.value(FileSettings.undoHistoryKey)?.int else { return }
        let dropping = max(0, (link.snapshot?.undoSteps ?? 0) - steps)
        if dropping > 0 {
            shortening = (steps, dropping)
        } else {
            link.edit(FileSettings.undoHistoryKey, to: .int(steps))
        }
    }
}

/// The watch's Text Extensions, with a field to add one and swipe to delete.
struct TextExtensionsScreen: View {
    @Environment(PhoneLink.self) private var link
    @State private var typed = ""
    @State private var problem: TextExtensionProblem?

    /// The list in written form: each entry normalized, dropping any that's
    /// invalid or repeated.
    private var extensions: [String] {
        var seen = Set<String>()
        return (link.value(FileSettings.textExtensionsKey)?.strings ?? [])
            .map(FileSettings.normalizedExtension)
            .filter { FileSettings.isWrittenTextExtensions([$0]) && seen.insert($0).inserted }
    }

    var body: some View {
        List {
            Section {
                TextField("Add Extension", text: $typed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(add)
                    .onChange(of: typed) { problem = nil }
                if let problem {
                    Text(problem.reason)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } footer: {
                EditNote(key: FileSettings.textExtensionsKey)
            }
            Section {
                ForEach(extensions, id: \.self) { ext in
                    Text(verbatim: ".\(ext)")
                }
                .onDelete { offsets in
                    var list = extensions
                    list.remove(atOffsets: offsets)
                    save(list)
                }
            } footer: {
                Text("Files with these extensions are treated as text.")
            }
        }
        .navigationTitle("Text Extensions")
    }

    /// Adds what was typed, or says why it can't.
    private func add() {
        guard !typed.isEmpty else { return }
        if let refused = FileSettings.textExtensionProblem(typed, existing: extensions) {
            problem = refused
            return
        }
        save(extensions + [FileSettings.normalizedExtension(typed)])
        typed = ""
    }

    private func save(_ list: [String]) {
        link.edit(FileSettings.textExtensionsKey, to: .strings(list))
    }
}

#Preview {
    NavigationStack {
        FileSettingsScreen()
    }
    .environment(PhoneLink())
}
