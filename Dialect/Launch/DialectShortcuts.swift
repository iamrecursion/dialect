import AppIntents

/// Both intents as App Shortcuts: in Shortcuts, Siri and the Action Button with
/// no setup.
struct DialectShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumeOrNewSessionIntent(),
            phrases: ["Resume a session in \(.applicationName)", "Resume \(.applicationName)"],
            shortTitle: "Resume or New",
            systemImageName: "playpause")
        AppShortcut(
            intent: NewSessionIntent(),
            phrases: [
                "New session in \(.applicationName)", "Start a new \(.applicationName) session",
            ],
            shortTitle: "New Session",
            systemImageName: "square.and.pencil")
    }
}
