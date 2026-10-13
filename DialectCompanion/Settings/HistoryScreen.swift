import SwiftUI

/// The watch's Settings › History: Recents' settings.
struct HistoryScreen: View {
    @Environment(PhoneLink.self) private var link

    var body: some View {
        List {
            SettingPicker(
                title: "Show Last", key: RecentsSettings.showLastKey,
                choices: RecentsSettings.showLastChoices
            ) { Text("\($0) Items") }
        }
        .navigationTitle("History")
    }
}

#Preview {
    NavigationStack {
        HistoryScreen()
    }
    .environment(PhoneLink())
}
