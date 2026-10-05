import SwiftUI

/// Settings › Files.
struct FileSettingsView: View {
    @AppStorage(FileSettings.confirmExtensionChangesKey) private var confirmExtensionChanges =
        FileSettings.confirmExtensionChangesDefault
    @AppStorage(FileSettings.emptyTrashAfterKey) private var emptyTrashAfter =
        FileSettings.emptyTrashAfterDefault

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
            }
        }
        .navigationTitle("Files")
        .onAppear { textExtensionCount = TextExtensionsView.stored().count }
    }
}

#Preview {
    NavigationStack {
        FileSettingsView()
    }
}
