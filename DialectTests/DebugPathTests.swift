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

    /// `more:` opens an item's More screen over the folders it's in.
    @Test func opensAnItemsMore() {
        let notes = FilePath(components: ["notes"])
        #expect(
            Route.debugPath("more:notes/todo.txt", creditsPages: pages) == [
                .files, .folder(notes), .itemMore(notes.appending("todo.txt")),
            ])
        #expect(
            Route.debugPath("files/more:readme", creditsPages: pages) == [
                .files, .itemMore(FilePath(components: ["readme"])),
            ])
    }

    @Test func opensTheBinAddAndClipboard() {
        #expect(Route.debugPath("files/trash", creditsPages: pages) == [.files, .bin])
        #expect(Route.debugPath("files/add", creditsPages: pages) == [.files, .add(.root)])
        #expect(
            Route.debugPath("files/clipboard", creditsPages: pages) == [.files, .clipboard(.root)])
        #expect(
            Route.debugPath("files/new-session", creditsPages: pages) == [
                .files, .newItem(.session, in: .root),
            ])
        #expect(Route.debugPath("files/new-nope", creditsPages: pages) == [.files])
        #expect(
            Route.debugPath("settings/file-settings/text-extensions", creditsPages: pages) == [
                .settings, .fileSettings, .textExtensions,
            ])
    }

    @Test func walksCreditsPagesByTitle() {
        #expect(
            Route.debugPath("settings/credits/Licence texts/CBORCoding", creditsPages: pages) == [
                .settings, .credits, .creditsPage(pages[1]), .creditsPage(license),
            ])
    }

    /// `folder:` takes the rest of the path as a folder below Files' root, with
    /// a route per level so Back climbs them.
    @Test func opensFolders() {
        let scripts = FilePath(components: ["scripts"])
        #expect(
            Route.debugPath("files/folder:scripts/lib", creditsPages: pages) == [
                .files, .folder(scripts), .folder(scripts.appending("lib")),
            ])
        #expect(
            Route.debugPath("folder:notes", creditsPages: pages) == [
                .files, .folder(FilePath(components: ["notes"])),
            ])
        #expect(Route.debugPath("files/folder:", creditsPages: pages) == [.files])
    }

    @Test func stopsAtTheFirstUnknownSegment() {
        #expect(Route.debugPath("settings/nope/runtime", creditsPages: pages) == [.settings])
        #expect(
            Route.debugPath("settings/credits/Nope", creditsPages: pages) == [.settings, .credits])
        #expect(
            Route.debugPath("settings/credits/LispKit", creditsPages: nil) == [.settings, .credits])
    }
}
