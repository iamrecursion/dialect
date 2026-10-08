import SwiftUI
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
        #expect(Route.path(notes).filePath == notes)
        #expect(Route.bin.filePath == nil)
        #expect(Route.settings.filePath == nil)
        #expect(Route.folderRoute(for: .root) == .files)
        #expect(Route.folderRoute(for: notes) == .folder(notes))
        #expect(notes.appending("a").isWithin(notes))
        #expect(notes.isWithin(notes))
        #expect(!FilePath(components: ["notesy"]).isWithin(notes))
        #expect(notes.isWithin(.root))
    }

    // MARK: Show in Files

    /// The folders are pushed, so it animates as a push, then what was under
    /// them goes, so Back climbs the folders to the main menu. The reveal waits
    /// for that, as dropping what's under the folder rebuilds its screen.
    @Test func showPushesTheFoldersThenDropsWhatWasUnder() async {
        let item = FilePath(components: ["a", "b", "x.txt"])
        let navigation = Navigation(path: [.recents])
        navigation.replaceDelay = .zero
        navigation.show(item)
        let folders: [Route] = [
            .files, .folder(FilePath(components: ["a"])), .folder(item.parent!),
        ]
        #expect(navigation.path == [.recents] + folders)
        #expect(navigation.revealing == nil)
        await navigation.pendingShow?.value
        #expect(navigation.path == folders)
        #expect(navigation.revealing == item)
    }

    /// A replace made before the drop, such as from an item's More, leaves it
    /// to happen.
    @Test func showKeepsItsDropThroughAReplace() async {
        let item = FilePath(components: ["notes", "todo.txt"])
        let navigation = Navigation(path: [.recents])
        navigation.replaceDelay = .zero
        navigation.show(item)
        navigation.push(.itemMore(item))
        navigation.replaceTop(with: .folderInfo(item))
        await navigation.pendingShow?.value
        await navigation.pendingDrop?.value
        #expect(navigation.path == Navigation.folders(to: notes) + [.folderInfo(item)])
    }

    @Test func showsAnItemAtTheRoot() async {
        let navigation = Navigation(path: [.recents])
        navigation.replaceDelay = .zero
        navigation.show(FilePath(components: ["readme"]))
        await navigation.pendingShow?.value
        #expect(navigation.path == [.files])
    }

    /// Back before the drop still leaves Files at the bottom; Back all the way
    /// to Recents leaves it be.
    @Test func showDropsWhatWasUnderAfterABack() async {
        let item = FilePath(components: ["notes", "todo.txt"])
        let navigation = Navigation(path: [.recents])
        navigation.replaceDelay = .zero
        navigation.show(item)
        navigation.pop()
        await navigation.pendingShow?.value
        #expect(navigation.path == [.files])
        #expect(navigation.revealing == nil)

        let back = Navigation(path: [.recents])
        back.replaceDelay = .zero
        back.show(item)
        back.path = [.recents]
        await back.pendingShow?.value
        #expect(back.path == [.recents])
    }

    /// Only the item's folder has the reveal, until it ends it.
    @Test func theRevealLastsUntilItsFolderEndsIt() async {
        let item = FilePath(components: ["notes", "todo.txt"])
        let navigation = Navigation(path: [.recents])
        navigation.replaceDelay = .zero
        navigation.show(item)
        await navigation.pendingShow?.value
        #expect(navigation.reveal(in: .root) == nil)
        #expect(navigation.reveal(in: FilePath(components: ["notes"])) == item)
        #expect(navigation.reveal(in: FilePath(components: ["notes"])) == item)
        navigation.endReveal()
        #expect(navigation.reveal(in: FilePath(components: ["notes"])) == nil)
    }

    /// A reveal not taken goes once its folder is no longer on top, so a later
    /// visit doesn't highlight anything.
    @Test func theRevealGoesWhenItsFolderLeavesTheTop() async {
        let item = FilePath(components: ["notes", "todo.txt"])
        let navigation = Navigation(path: [.recents])
        navigation.replaceDelay = .zero
        navigation.show(item)
        await navigation.pendingShow?.value
        #expect(navigation.revealing == item)
        navigation.push(.folderMore(FilePath(components: ["notes"])))
        #expect(navigation.revealing == nil)

        navigation.path = [.recents]
        navigation.show(item)
        await navigation.pendingShow?.value
        navigation.path.removeLast()
        #expect(navigation.revealing == nil)
    }

    /// Showing a hidden item lists hidden items in its folder while the folder
    /// stays on the path, whatever Show Hidden says.
    @Test func showingAHiddenItemShowsHiddenItemsInItsFolder() async {
        let item = FilePath(components: ["notes", ".draft.md"])
        let navigation = Navigation(path: [.recents])
        navigation.replaceDelay = .zero
        navigation.show(item)
        await navigation.pendingShow?.value
        #expect(navigation.showsHidden(in: notes))
        #expect(!navigation.showsHidden(in: .root))

        // Screens over it keep it; leaving the folder ends it.
        navigation.push(.folderMore(notes))
        #expect(navigation.showsHidden(in: notes))
        navigation.pop()
        navigation.pop()
        #expect(!navigation.showsHidden(in: notes))
        navigation.push(.folder(notes))
        #expect(!navigation.showsHidden(in: notes))
    }

    /// An item that isn't hidden, even inside a hidden folder, is listed
    /// anyway.
    @Test func showingAnItemThatIsntHiddenLeavesHiddenItemsHidden() async {
        let navigation = Navigation(path: [.recents])
        navigation.replaceDelay = .zero
        navigation.show(FilePath(components: [".config", "init.scm"]))
        await navigation.pendingShow?.value
        #expect(!navigation.showsHidden(in: FilePath(components: [".config"])))
        #expect(!navigation.showsHidden(in: .root))
    }

    /// The highlight starts from the rows' own platter, so it fades into it.
    @Test func theHighlightFadesIntoThePlatter() {
        let accent = Color.Resolved(colorSpace: .sRGB, red: 0.5, green: 0.8, blue: 0.4)
        let off = RowHighlight.color(accent: accent, amount: 0)
        #expect(off.red == RowHighlight.platter.red)
        #expect(off.blue == RowHighlight.platter.blue)
        let lit = RowHighlight.color(accent: accent, amount: 1)
        let expected = RowHighlight.platter.green + (0.8 - RowHighlight.platter.green) * 0.45
        #expect(abs(lit.green - expected) < 0.001)
    }

    @Test func popsToTheMainMenu() {
        let navigation = Navigation(path: [.files, .folder(notes), .path(notes)])
        navigation.popToRoot()
        #expect(navigation.path.isEmpty)
    }

    @Test func replacingAnEmptyNavigationPushes() {
        let navigation = Navigation()
        navigation.replaceTop(with: .files)
        #expect(navigation.path == [.files])
        #expect(navigation.pendingDrop == nil)
    }
}
