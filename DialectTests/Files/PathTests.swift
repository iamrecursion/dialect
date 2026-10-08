import Testing

@testable import Dialect

/// Path: the levels from the folder down to the main menu, and the question
/// asked before a jump drops a selection.
struct PathTests {
    @Test func listsTheFolderDownToTheMainMenu() {
        let levels = PathScreen.levels(
            for: FilePath(components: ["scripts", "demo.dial", "lib"]), showExtensions: true)
        #expect(levels.map(\.title) == ["lib", "demo.dial", "scripts", "Files", "Menu"])
        #expect(
            levels.map(\.symbol) == [
                .system("folder.fill"), .custom("session"), .system("folder.fill"),
                .system("folder.fill"), .system("list.bullet.below.rectangle"),
            ])
        #expect(
            levels.map(\.route) == [
                .folder(FilePath(components: ["scripts", "demo.dial", "lib"])),
                .folder(FilePath(components: ["scripts", "demo.dial"])),
                .folder(FilePath(components: ["scripts"])), .files, nil,
            ])
        #expect(levels.map(\.isCurrent) == [true, false, false, false, false])
    }

    @Test func listsFilesItself() {
        let levels = PathScreen.levels(for: .root, showExtensions: true)
        #expect(levels.map(\.title) == ["Files", "Menu"])
        #expect(levels.map(\.isCurrent) == [true, false])
    }

    /// An entered session's name follows Show File Extensions, as its title
    /// does.
    @Test func namesSessionsAsTheirTitlesDo() {
        let levels = PathScreen.levels(
            for: FilePath(components: ["demo.dial"]), showExtensions: false)
        #expect(levels.first?.title == "demo")
    }

    @Test func asksBeforeDroppingASelection() {
        #expect(
            PathScreen.question(selected: 2, going: "scripts")
                == "Deselect 2 items and go to scripts?")
        #expect(
            PathScreen.question(selected: 1, going: "Files") == "Deselect 1 item and go to Files?")
        #expect(PathScreen.asks(selected: 0) == false)
        #expect(PathScreen.asks(selected: 1))
    }
}
