import SwiftUI

/// Settings › History: Recents' settings.
struct RecentsSettingsView: View {
    @AppStorage(RecentsSettings.showLastKey) private var showLast =
        RecentsSettings.showLastDefault

    var body: some View {
        List {
            Picker("Show Last", selection: $showLast) {
                ForEach(RecentsSettings.showLastChoices, id: \.self) { count in
                    Text("\(count) Items").tag(count)
                }
            }
            .pickerStyle(.navigationLink)
        }
        .navigationTitle("History")
    }
}

#Preview {
    NavigationStack {
        RecentsSettingsView()
    }
}
