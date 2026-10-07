import SwiftUI

/// Settings › Files.
struct FileSettingsView: View {
    @AppStorage(FileSettings.confirmExtensionChangesKey) private var confirmExtensionChanges =
        FileSettings.confirmExtensionChangesDefault
    @AppStorage(FileSettings.emptyTrashAfterKey) private var emptyTrashAfter =
        FileSettings.emptyTrashAfterDefault
    @AppStorage(FileSettings.undoHistoryKey) private var undoHistory =
        FileSettings.undoHistoryDefault

    /// A shorter Undo History that would drop steps, waiting for its
    /// confirmation.
    @State private var shortening: (steps: Int, dropping: Int)?

    /// The number of text extensions.
    @State private var textExtensionCount = 0

    @AppStorage(FileSettings.showExtensionsKey) private var showExtensions =
        FileSettings.showExtensionsDefault
    @AppStorage(FileSettings.showDetailsKey) private var showDetails =
        FileSettings.showDetailsDefault
    @AppStorage(FileSettings.relativeModifiedKey) private var relativeModified =
        FileSettings.relativeModifiedDefault
    @AppStorage(FileSettings.foldersFirstKey) private var foldersFirst =
        FileSettings.foldersFirstDefault
    @AppStorage(FileSettings.showHiddenKey) private var showHidden =
        FileSettings.showHiddenDefault

    var body: some View {
        List {
            Toggle("File Extensions", isOn: $showExtensions)
            Toggle("Details", isOn: $showDetails)
            Picker("Modified", selection: $relativeModified) {
                Text("Relative").tag(true)
                Text("Date and Time").tag(false)
            }
            .pickerStyle(.navigationLink)
            Toggle("Folders First", isOn: $foldersFirst)
            Toggle("Hidden Files", isOn: $showHidden)

            Section {
                Toggle("Confirm Extension Changes", isOn: $confirmExtensionChanges)
                NavigationLink(value: Route.textExtensions) {
                    LabeledContent("Text Extensions", value: textExtensionCount.formatted())
                }
            }

            Section {
                Picker("Empty Trash After", selection: $emptyTrashAfter) {
                    ForEach(FileSettings.emptyTrashAfterChoices, id: \.self) { days in
                        Text(FileSettings.emptyTrashAfterTitle(days)).tag(days)
                    }
                }
                .pickerStyle(.navigationLink)
                Picker("Undo History", selection: Binding(get: { undoHistory }, set: choose)) {
                    ForEach(FileSettings.undoHistoryChoices, id: \.self) { steps in
                        Text("\(steps) Steps").tag(steps)
                    }
                }
                .pickerStyle(.navigationLink)
            }
        }
        .navigationTitle("Files")
        .alert(
            "Shorten Undo History?",
            isPresented: Binding(
                get: { shortening != nil }, set: { if !$0 { shortening = nil } }),
            presenting: shortening
        ) { shortening in
            Button("Shorten", role: .destructive) { shorten(to: shortening.steps) }
            Button("Cancel", role: .cancel) {}
        } message: { shortening in
            Text(FileSettings.shorteningNote(dropping: shortening.dropping))
        }
        .onAppear { textExtensionCount = TextExtensionsView.stored().count }
    }

    /// Sets Undo History, first asking when a shorter one would drop steps.
    private func choose(_ steps: Int) {
        let dropping = FilesRoot.operations.history.read().excess(over: steps)
        if dropping > 0 {
            shortening = (steps, dropping)
        } else {
            undoHistory = steps
        }
    }

    private func shorten(to steps: Int) {
        Task {
            try? await FilesRoot.operations.trimHistory(to: steps)
            undoHistory = steps
        }
    }
}

#Preview {
    NavigationStack {
        FileSettingsView()
    }
}
