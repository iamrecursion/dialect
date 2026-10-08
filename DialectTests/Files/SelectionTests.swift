import Testing

@testable import Dialect

/// Select mode's rules, without the screens: entering, toggling, Select All,
/// items leaving, ending, and the title.
@MainActor
struct SelectionTests {
    private let notes = Route.folder(FilePath("notes"))
    private let items = ["a.txt", "b.txt", "c.txt"].map { FilePath("notes/\($0)") }

    @Test func beginsWithTheSwipedItemOrNothing() {
        let selection = FileSelection()
        #expect(!selection.isSelecting(on: notes))
        selection.begin(on: notes, with: items[1])
        #expect(selection.isSelecting(on: notes))
        #expect(!selection.isSelecting(on: .files))
        #expect(selection.items == [items[1]])

        selection.begin(on: .files)
        #expect(selection.isSelecting(on: .files))
        #expect(!selection.isSelecting(on: notes))
        #expect(selection.items.isEmpty)
    }

    @Test func togglesAnItem() {
        let selection = FileSelection()
        selection.begin(on: notes)
        selection.toggle(items[0])
        selection.toggle(items[2])
        #expect(selection.items == [items[0], items[2]])
        selection.toggle(items[0])
        #expect(selection.items == [items[2]])
    }

    /// Select All takes what's listed; everything is selected only when
    /// something is listed.
    @Test func selectsAndDeselectsEverythingListed() {
        let selection = FileSelection()
        selection.begin(on: notes, with: items[0])
        #expect(!selection.hasEverything)
        selection.list(items)
        selection.selectAll()
        #expect(selection.items == Set(items))
        #expect(selection.hasEverything)
        selection.deselectAll()
        #expect(selection.items.isEmpty)
        #expect(!selection.hasEverything)

        selection.list([])
        selection.selectAll()
        #expect(!selection.hasEverything)
    }

    /// Items no longer listed, such as deleted elsewhere or hidden again, leave
    /// the selection.
    @Test func dropsItemsThatAreNoLongerListed() {
        let selection = FileSelection()
        selection.begin(on: notes)
        selection.list(items)
        selection.selectAll()
        selection.list([items[0], items[2]])
        #expect(selection.items == [items[0], items[2]])
        #expect(selection.hasEverything)
    }

    @Test func givesTheSelectionInListedOrder() {
        let selection = FileSelection()
        selection.begin(on: notes)
        selection.list(items)
        selection.toggle(items[2])
        selection.toggle(items[0])
        #expect(selection.selected == [items[0], items[2]])
    }

    /// Back ends it; Settings, pushed over the folder, doesn't.
    @Test func endsWhenItsScreenLeavesThePath() {
        let selection = FileSelection()
        selection.begin(on: notes, with: items[0])
        selection.follow([.files, notes, .settings, .fileSettings])
        #expect(selection.isSelecting(on: notes))
        #expect(selection.items == [items[0]])
        selection.follow([.files])
        #expect(!selection.isSelecting(on: notes))
        #expect(selection.items.isEmpty)
    }

    @Test func endsWithNothingSelected() {
        let selection = FileSelection()
        selection.begin(on: notes, with: items[0])
        selection.list(items)
        selection.end()
        #expect(!selection.isSelecting(on: notes))
        #expect(selection.items.isEmpty)
        #expect(selection.listed.isEmpty)
    }

    /// Delete Selected ends select mode and hands the items to their screen,
    /// once.
    @Test func handsADeletionToItsScreen() {
        let selection = FileSelection()
        selection.begin(on: notes)
        selection.list(items)
        selection.toggle(items[1])
        selection.deleteSelected()
        #expect(!selection.isSelecting(on: notes))
        #expect(selection.takeDeletion(on: .files) == nil)
        #expect(selection.takeDeletion(on: notes) == [items[1]])
        #expect(selection.takeDeletion(on: notes) == nil)
    }

    /// The circle takes the icon's place on the 42 mm (187 pt) at the default
    /// text size, where the icon's slot is 30 pt, but not on the 46 mm (208 pt)
    /// or the Ultra (211 pt) until the text is larger.
    @Test func replacesTheIconWhereTheScreenIsNarrow() {
        #expect(RowIcon.circleReplacesIcon(screenWidth: 187, iconWidth: 30))
        #expect(!RowIcon.circleReplacesIcon(screenWidth: 208, iconWidth: 30))
        #expect(!RowIcon.circleReplacesIcon(screenWidth: 211, iconWidth: 30))
        #expect(RowIcon.circleReplacesIcon(screenWidth: 211, iconWidth: 40))
    }

    @Test func titlesSelectMode() {
        #expect(FileSelection.title(selected: 0) == "Select Items")
        #expect(FileSelection.title(selected: 1) == "1 Selected")
        #expect(FileSelection.title(selected: 2) == "2 Selected")
    }
}
