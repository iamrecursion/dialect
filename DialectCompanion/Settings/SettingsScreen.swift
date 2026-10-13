import SwiftUI

/// The watch's settings, in its groups, then Credits.
struct SettingsScreen: View {
    @Environment(PhoneLink.self) private var link

    var body: some View {
        List {
            if link.snapshot != nil {
                // The watch's groups, in its order; those it has no screen for yet are placeholders
                // here too.
                Section {
                    PlaceholderRow(title: "Editor", systemImage: "keyboard")
                    PlaceholderRow(title: "Sessions", systemImage: "document.badge.gearshape")
                    NavigationLink {
                        AppearanceScreen()
                    } label: {
                        SettingsLabel(title: "Appearance", systemImage: "paintpalette")
                    }
                    PlaceholderRow(
                        title: "Runtime", systemImage: "gauge.with.dots.needle.100percent")
                    NavigationLink {
                        FileSettingsScreen()
                    } label: {
                        SettingsLabel(title: "Files", systemImage: "folder.badge.gearshape")
                    }
                    NavigationLink {
                        HistoryScreen()
                    } label: {
                        SettingsLabel(title: "History", systemImage: RecentsSymbol.recents)
                    }
                    PlaceholderRow(title: "Downloader", systemImage: "arrow.down.circle.dotted")
                    PlaceholderRow(title: "Companion", systemImage: "ipad.landscape.and.applewatch")
                }
            } else if link.status != nil {
                Section {
                    Text("Your watch's settings aren't available. The Watch tab says why.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                NavigationLink {
                    CreditsScreen()
                } label: {
                    SettingsLabel(title: "Credits", systemImage: "list.clipboard")
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { link.forgetChangedOnWatch() }
    }
}

/// A group the watch has no screen for yet.
private struct PlaceholderRow: View {
    let title: LocalizedStringResource
    let systemImage: String

    var body: some View {
        NavigationLink {
            PlaceholderScreen(title: title)
        } label: {
            SettingsLabel(title: title, systemImage: systemImage)
        }
    }
}

/// A row's icon, in the accent color, and its title.
struct SettingsLabel: View {
    let title: LocalizedStringResource
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
    .environment(PhoneLink())
}
