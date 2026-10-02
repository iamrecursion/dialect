import AppIntents

// The intents are shared with the widget extension. They open the app, so the system runs
// `perform()` in the app's process, where the router is; the extension only needs them to exist.

/// Opens Dialect on the latest session, or on a new one if there is none.
struct ResumeOrNewSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume or New Session"
    static let description = IntentDescription(
        "Opens your latest session in Dialect, or a new one if there is none.")
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
            LaunchRouter.shared.request(.resumeOrNew)
        #endif
        return .result()
    }
}

/// Opens Dialect on a new session.
struct NewSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "New Session"
    static let description = IntentDescription("Opens a new session in Dialect.")
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
            LaunchRouter.shared.request(.new)
        #endif
        return .result()
    }
}
