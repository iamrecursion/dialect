import SwiftUI

/// Select mode: the screen it's on and the items picked there.
///
/// Folders share the same selection state, though the trash bin's selection
/// state is separate. A screen is in select mode wwhile the selection is active
/// on it.
@MainActor @Observable
final class Selection<Item: Hashable> {
    /// The screen in select mode; `nil` outside it.
    private(set) var screen: Route?

    /// What the screen lists, which Select All takes.
    private(set) var listed: [Item] = []
    private(set) var items: Set<Item> = []

    /// Items a More screen has handed back to the screen to delete, which it
    /// takes with `takeDeletion(on:)`.
    private(set) var deletion: (screen: Route, items: [Item])?

    func isSelecting(on route: Route) -> Bool {
        return screen == route
    }

    /// The selected items, in the order listed.
    var selected: [Item] {
        return listed.filter(items.contains)
    }

    /// Whether everything listed is selected, and something is.
    var hasEverything: Bool {
        return !listed.isEmpty && listed.allSatisfy(items.contains)
    }

    /// Enters select mode on `screen`, with `item` selected when given.
    func begin(on screen: Route, with item: Item? = nil) {
        self.screen = screen
        items = item.map { [$0] } ?? []
    }

    func toggle(_ item: Item) {
        if items.remove(item) == nil {
            items.insert(item)
        }
    }

    func selectAll() {
        items = Set(listed)
    }

    func deselectAll() {
        items = []
    }

    /// What the screen now lists. Selected items no longer among them leave the
    /// selection.
    func list(_ items: [Item]) {
        listed = items
        self.items.formIntersection(items)
    }

    func end() {
        screen = nil
        listed = []
        items = []
    }

    /// Ends select mode once its screen has left the navigation path.
    func follow(_ path: [Route]) {
        if let screen, !path.contains(screen) {
            end()
        }
    }

    /// Ends select mode, handing the selection to its screen to delete.
    func deleteSelected() {
        guard let screen else { return }
        deletion = (screen, selected)
        end()
    }

    /// The items handed back to delete on `route`, once.
    func takeDeletion(on route: Route) -> [Item]? {
        guard let deletion, deletion.screen == route else { return nil }
        self.deletion = nil
        return deletion.items
    }

    /// The title in select mode: "2 Selected", or "Select Items" with nothing
    /// selected.
    nonisolated static func title(selected count: Int) -> String {
        return count == 0
            ? String(localized: "Select Items") : String(localized: "\(count) Selected")
    }
}

/// The folders' selection.
typealias FileSelection = Selection<FilePath>

/// The Trash's selection, by bin item.
typealias BinSelection = Selection<UUID>

/// Select mode's icons.
enum SelectSymbol {
    static let select = "checkmark.circle.badge.plus"
    static let done = "checkmark"
}
