import AppIntents
import Testing

@testable import Dialect

/// The shortcut actions. They share the app-wide router, so one at a time.
@MainActor
@Suite(.serialized)
struct LaunchIntentTests {
    @Test func resumeOrNewAsksForTheLatestOrANewSession() async throws {
        _ = LaunchRouter.shared.take()
        _ = try await ResumeOrNewSessionIntent().perform()
        #expect(LaunchRouter.shared.take() == .resumeOrNew)
    }

    @Test func newAsksForANewSession() async throws {
        _ = LaunchRouter.shared.take()
        _ = try await NewSessionIntent().perform()
        #expect(LaunchRouter.shared.take() == .new)
    }

    /// Both bring the app to the front: a session is something to look at.
    @Test func bothOpenTheApp() {
        #expect(ResumeOrNewSessionIntent.supportedModes == .foreground)
        #expect(NewSessionIntent.supportedModes == .foreground)
    }

    /// Registered as App Shortcuts, so they are in Shortcuts, Siri and the
    /// Action Button without any setup.
    @Test func bothAreAppShortcuts() {
        #expect(DialectShortcuts.appShortcuts.count == 2)
    }
}
