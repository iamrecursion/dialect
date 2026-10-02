import Testing

@testable import Dialect

struct DebugPathTests {
    let license = NoticeSection(title: "CBORCoding", blocks: [.plain("MIT")], subsections: [])
    var pages: [NoticeSection] {
        return [
            NoticeSection(title: "LispKit", blocks: [], subsections: []),
            NoticeSection(title: "Licence texts", blocks: [], subsections: [license]),
        ]
    }

    @Test func namesRoutes() {
        #expect(
            Route.debugPath("settings/runtime", creditsPages: pages) == [
                .settings, .runtimeSettings,
            ])
        #expect(Route.debugPath("new-repl", creditsPages: pages) == [.newREPL])
        #expect(
            Route.debugPath("settings/appearance/accent-color", creditsPages: pages) == [
                .settings, .appearanceSettings, .accentColor,
            ])
        #expect(
            Route.debugPath("downloader", creditsPages: pages) == [.downloader])
        #expect(
            Route.debugPath("settings/file-settings", creditsPages: pages) == [
                .settings, .fileSettings,
            ])
        #expect(
            Route.debugPath("settings/downloader-settings", creditsPages: pages) == [
                .settings, .downloaderSettings,
            ])
    }

    @Test func walksCreditsPagesByTitle() {
        #expect(
            Route.debugPath("settings/credits/Licence texts/CBORCoding", creditsPages: pages) == [
                .settings, .credits, .creditsPage(pages[1]), .creditsPage(license),
            ])
    }

    @Test func stopsAtTheFirstUnknownSegment() {
        #expect(Route.debugPath("settings/nope/runtime", creditsPages: pages) == [.settings])
        #expect(
            Route.debugPath("settings/credits/Nope", creditsPages: pages) == [.settings, .credits])
        #expect(
            Route.debugPath("settings/credits/LispKit", creditsPages: nil) == [.settings, .credits])
    }
}
