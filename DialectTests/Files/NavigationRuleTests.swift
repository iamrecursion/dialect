import Testing

@testable import Dialect

/// More never stays in the history: what it opens replaces it, and what it does
/// pops it.
@MainActor
struct NavigationRuleTests {
    private let notes = FilePath(components: ["notes"])

    @Test func navigationPushesAndPops() {
        let navigation = Navigation()
        navigation.push(.files)
        navigation.push(.folderMore(.root))
        #expect(navigation.path == [.files, .folderMore(.root)])
        navigation.pop()
        #expect(navigation.path == [.files])
        navigation.pop()
        navigation.pop()
        #expect(navigation.path.isEmpty)
    }

    /// Replacing pushes, so it animates as a push, then drops More from under
    /// the new screen once the push has settled.
    @Test func replacingPushesThenDropsMore() async {
        let navigation = Navigation(path: [.files, .folderMore(.root)])
        navigation.replaceDelay = .zero
        navigation.replaceTop(with: .sort(.root))
        #expect(navigation.path == [.files, .folderMore(.root), .sort(.root)])
        await navigation.pendingDrop?.value
        #expect(navigation.path == [.files, .sort(.root)])
        navigation.pop()
        #expect(navigation.path == [.files])
    }

    /// The system's Back button sets the path itself: backing out that way
    /// before More is dropped lands on More, and the drop leaves it be.
    @Test func replacingLeavesAPathThatsMovedOn() async {
        let navigation = Navigation(path: [.files, .folderMore(.root)])
        navigation.replaceDelay = .zero
        navigation.replaceTop(with: .sort(.root))
        navigation.path.removeLast()
        await navigation.pendingDrop?.value
        #expect(navigation.path == [.files, .folderMore(.root)])

        var path: [Route] = [.files, .folderMore(.root)]
        let dropped = path.drop(.folderMore(.root), under: .sort(.root))
        #expect(!dropped)
        #expect(path == [.files, .folderMore(.root)])
    }

    /// A choice made before More is dropped, such as a quick sort, still goes
    /// back to the folder.
    @Test func poppingARecentReplaceSkipsMore() async {
        let navigation = Navigation(path: [.files, .folderMore(.root)])
        navigation.replaceDelay = .seconds(60)
        navigation.replaceTop(with: .sort(.root))
        navigation.pop()
        #expect(navigation.path == [.files])
        await navigation.pendingDrop?.value
        #expect(navigation.path == [.files])
    }

    /// Going deeper before More is dropped, such as Settings › Files, still
    /// drops it from under the screen that replaced it.
    @Test func droppingFindsMoreUnderDeeperScreens() async {
        let navigation = Navigation(path: [.files, .folderMore(.root)])
        navigation.replaceDelay = .zero
        navigation.replaceTop(with: .settings)
        navigation.push(.fileSettings)
        await navigation.pendingDrop?.value
        #expect(navigation.path == [.files, .settings, .fileSettings])
    }

    /// A second replace before the first's drop takes over from it: the first's
    /// drop can't clear the second's.
    @Test func aSecondReplaceTakesOver() async {
        let navigation = Navigation(path: [.files, .folderMore(.root)])
        navigation.replaceDelay = .seconds(60)
        navigation.replaceTop(with: .sort(.root))
        let first = navigation.pendingDrop
        // The system Back button, then another of More's screens.
        navigation.path.removeLast()
        navigation.replaceTop(with: .group(.root))
        await first?.value
        navigation.pop()
        #expect(navigation.path == [.files])
    }

    // MARK: Going back to a folder, and leaving a deleted one

    /// Making an item goes back to its folder, past Add's name screen.
    @Test func popsToARoute() {
        let navigation = Navigation(
            path: [.files, .folder(notes), .newItem(.file, in: notes)])
        navigation.pop(to: .folder(notes))
        #expect(navigation.path == [.files, .folder(notes)])
        // Already there, or not on the path at all: nothing changes.
        navigation.pop(to: .folder(notes))
        navigation.pop(to: .settings)
        #expect(navigation.path == [.files, .folder(notes)])
    }

    /// Popping past a replace whose drop is still to come cancels the drop, so
    /// it can't later take a screen that happens to match.
    @Test func poppingToARouteCancelsAPendingReplace() async {
        let navigation = Navigation(path: [.files, .folder(notes), .add(notes)])
        navigation.replaceDelay = .seconds(60)
        navigation.replaceTop(with: .newItem(.folder, in: notes))
        let drop = navigation.pendingDrop
        navigation.pop(to: .folder(notes))
        #expect(navigation.path == [.files, .folder(notes)])
        navigation.push(.add(notes))
        navigation.push(.newItem(.folder, in: notes))
        await drop?.value
        #expect(
            navigation.path == [.files, .folder(notes), .add(notes), .newItem(.folder, in: notes)])
    }

    /// Deleting a folder from its own More screen leaves it and everything
    /// below it, ending on its parent.
    @Test func leavesADeletedFolder() {
        let navigation = Navigation(path: [.files, .folder(notes), .folderMore(notes)])
        navigation.leave(notes)
        #expect(navigation.path == [.files])
    }

    @Test func leavesFromDeepBelowTheDeletedFolder() {
        let sub = notes.appending("sub")
        let navigation = Navigation(
            path: [
                .files, .folder(notes), .folder(sub), .itemMore(sub.appending("a.txt")), .settings,
            ])
        navigation.leave(notes)
        #expect(navigation.path == [.files])
    }

    /// Deleting a row's item from its More screen leaves only More.
    @Test func leavesAnItemsMore() {
        let todo = notes.appending("todo.txt")
        let navigation = Navigation(path: [.files, .folder(notes), .itemMore(todo)])
        navigation.leave(todo)
        #expect(navigation.path == [.files, .folder(notes)])
    }

    @Test func leavesNothingWhenTheFolderIsntOnThePath() {
        let navigation = Navigation(path: [.files, .folder(notes)])
        navigation.leave(FilePath(components: ["scripts"]))
        navigation.leave(FilePath(components: ["notesy"]))
        #expect(navigation.path == [.files, .folder(notes)])
    }

    @Test func knowsWhatEachFilesRouteIsAbout() {
        #expect(Route.files.filePath == .root)
        #expect(Route.folder(notes).filePath == notes)
        #expect(Route.newItem(.session, in: notes).filePath == notes)
        #expect(Route.rename(notes).filePath == notes)
        #expect(Route.bin.filePath == nil)
        #expect(Route.settings.filePath == nil)
        #expect(Route.folderRoute(for: .root) == .files)
        #expect(Route.folderRoute(for: notes) == .folder(notes))
        #expect(notes.appending("a").isWithin(notes))
        #expect(notes.isWithin(notes))
        #expect(!FilePath(components: ["notesy"]).isWithin(notes))
        #expect(notes.isWithin(.root))
    }

    @Test func replacingAnEmptyNavigationPushes() {
        let navigation = Navigation()
        navigation.replaceTop(with: .files)
        #expect(navigation.path == [.files])
        #expect(navigation.pendingDrop == nil)
    }
}
