import Testing
import UIKit

@testable import Dialect

/// The menus' titles, SF Symbols and destinations, in order.
@MainActor
struct NavigationTests {
    @Test func topRow() {
        #expect(MainMenu.topRow.map(\.title.key) == ["New REPL", "Resume Session", "Sessions"])
        #expect(
            MainMenu.topRow.map(\.systemImage) == [
                "square.and.pencil", "playpause",
                "clock.arrow.trianglehead.counterclockwise.rotate.90",
            ])
        #expect(MainMenu.topRow.map(\.route) == [.newREPL, .resumeSession, .sessions])
    }

    /// `square.and.pencil`'s pencil tip sticks up above its square, so at
    /// `.title3` with the large symbol scale the square sits about 2.25 pt low
    /// beside the other icons (measured on the 42 mm and Ultra screenshots);
    /// only it is nudged.
    @Test func topRowOpticalOffsets() {
        #expect(MainMenu.topRow.map(\.opticalOffset) == [-2.25, 0, 0])
    }

    @Test func menuRows() {
        #expect(MainMenu.rows.map(\.title.key) == ["Files", "Downloader", "Settings"])
        #expect(MainMenu.rows.map(\.systemImage) == ["folder", "arrow.down.circle", "gear"])
        #expect(MainMenu.rows.map(\.route) == [.files, .downloader, .settings])
        #expect(MainMenu.rows.allSatisfy { $0.opticalOffset == 0 })
    }

    @Test func settingsRows() {
        #expect(
            SettingsView.rows.map(\.title.key) == [
                "Editor", "Sessions", "Appearance", "Runtime", "Files", "Downloader", "Companion",
            ])
        #expect(
            SettingsView.rows.map(\.systemImage) == [
                "keyboard", "document.badge.gearshape", "paintpalette",
                "gauge.with.dots.needle.100percent", "folder.badge.gearshape",
                "arrow.down.circle.dotted", "ipad.landscape.and.applewatch",
            ])
        #expect(
            SettingsView.rows.map(\.route) == [
                .editorSettings, .sessionSettings, .appearanceSettings, .runtimeSettings,
                .fileSettings, .downloaderSettings, .companionSettings,
            ])
        #expect(SettingsView.credits.title.key == "Credits")
        #expect(SettingsView.credits.systemImage == "list.clipboard")
        #expect(SettingsView.credits.route == .credits)
    }

    @Test func everySymbolExists() {
        let items = MainMenu.topRow + MainMenu.rows + SettingsView.rows + [SettingsView.credits]
        for item in items {
            #expect(UIImage(systemName: item.systemImage) != nil, "\(item.systemImage)")
        }
    }

    @Test func placeholderTitles() {
        let expected: [(Route, String)] = [
            (.resumeSession, "Resume Session"), (.sessions, "History"),
            (.editorSettings, "Editor"), (.sessionSettings, "Sessions"),
            (.runtimeSettings, "Runtime"),
            (.companionSettings, "Companion"), (.downloader, "Downloader"),
            (.downloaderSettings, "Downloader"),
        ]
        for (route, title) in expected {
            #expect(route.placeholderTitle?.key == title)
        }
        #expect(Route.newREPL.placeholderTitle == nil)
        #expect(Route.settings.placeholderTitle == nil)
        #expect(Route.credits.placeholderTitle == nil)
        #expect(Route.appearanceSettings.placeholderTitle == nil)
        #expect(Route.accentColor.placeholderTitle == nil)
        #expect(Route.fileSettings.placeholderTitle == nil)
        #expect(Route.files.placeholderTitle == nil)
        #expect(Route.itemMore(.root).placeholderTitle == nil)
        #expect(Route.add(.root).placeholderTitle == nil)
        #expect(Route.bin.placeholderTitle == nil)
        #expect(Route.clipboard(.root).placeholderTitle == nil)
    }

    @Test func appearanceRows() {
        #expect(AppearanceView.rows.map(\.title.key) == ["Accent Color"])
        #expect(AppearanceView.rows.map(\.systemImage) == ["swatchpalette"])
        #expect(AppearanceView.rows.map(\.route) == [.accentColor])
        #expect(UIImage(systemName: "swatchpalette") != nil)
    }

    /// The folder screen's buttons. Clipboard fills, with a count, while the
    /// clipboard holds items.
    @Test func folderButtons() {
        let notes = FilePath(components: ["notes"])
        let buttons = FolderScreen.buttons(for: notes, clipboardCount: 0)
        #expect(buttons.map(\.title.key) == ["Add", "Clipboard", "More"])
        #expect(
            buttons.map(\.systemImage) == ["plus.capsule", "list.clipboard", "ellipsis.circle"])
        #expect(buttons.map(\.route) == [.add(notes), .clipboard(notes), .folderMore(notes)])
        #expect(buttons.map(\.isDisabled) == [false, false, false])
        #expect(buttons.map(\.count) == [nil, nil, nil])

        let holding = FolderScreen.buttons(for: notes, clipboardCount: 3)
        #expect(holding[1].systemImage == "list.clipboard.fill")
        #expect(holding.map(\.count) == [nil, 3, nil])
        #expect(holding[1].countDescription == "3 items")
        #expect(FolderScreen.buttons(for: notes, clipboardCount: 1)[1].countDescription == "1 item")
        #expect(UIImage(systemName: "list.clipboard.fill") != nil)
        // The clipboard's clip sticks up above its board, which then sits about 1.5 pt low beside
        // its neighbors (measured on the 42 mm and Ultra screenshots).
        #expect(buttons.map(\.opticalOffset) == [0, -1.5, 0])
        for item in buttons {
            #expect(UIImage(systemName: item.systemImage) != nil, "\(item.systemImage)")
        }
    }

    /// In select mode the buttons are Done, Copy and More; Copy is grayed out
    /// with nothing selected.
    @Test func selectModeButtons() {
        let notes = FilePath(components: ["notes"])
        let none = FolderScreen.buttons(
            for: notes, clipboardCount: 3, selecting: true, selectedCount: 0)
        #expect(none.map(\.title.key) == ["Done", "Copy", "More"])
        #expect(none.map(\.systemImage) == ["checkmark", ClipboardSymbol.copy, "ellipsis.circle"])
        #expect(none.map(\.action) == [.done, .copy, nil])
        #expect(none.map(\.route) == [.folder(notes), .folder(notes), .folderMore(notes)])
        #expect(none.map(\.isDisabled) == [false, true, false])
        #expect(none.map(\.count) == [nil, nil, nil])
        #expect(Set(none.map(\.id)).count == 3)

        let two = FolderScreen.buttons(
            for: notes, clipboardCount: 0, selecting: true, selectedCount: 2)
        #expect(two.map(\.isDisabled) == [false, false, false])
        #expect(
            FolderScreen.buttons(for: .root, clipboardCount: 0, selecting: true)[0].route == .files)
        for item in none {
            #expect(UIImage(systemName: item.systemImage) != nil, "\(item.systemImage)")
        }
        #expect(UIImage(systemName: SelectSymbol.select) != nil)
    }

    /// A folder's More screen's items, in order.
    @Test func folderMoreItems() {
        #expect(
            FolderMoreScreen.Action.allCases.map(\.systemImage) == [
                "checklist.checked", "checklist.unchecked", "square.and.arrow.up", "trash",
                "arrow.up.arrow.down", "square.grid.3x1.below.line.grid.1x2", "eye", "info.circle",
                "trash", "trash.fill", "gear",
            ])
        #expect(
            FolderMoreScreen.Action.allCases.map(\.title.key) == [
                "Select All", "Deselect All", "Share", "Delete Selected", "Sort", "Group",
                "Show Hidden", "Folder Info", "Delete", "Trash", "Settings",
            ])
        for action in FolderMoreScreen.Action.allCases {
            #expect(UIImage(systemName: action.systemImage) != nil, "\(action.systemImage)")
        }
        #expect(UIImage(systemName: "eye.slash") != nil)
        #expect(UIImage(systemName: "info.circle") != nil)
    }

    /// In select mode, More starts with the selection's actions and loses the
    /// folder's Delete.
    @Test func folderMoreInSelectMode() {
        #expect(
            FolderMoreScreen.selectActions(hasEverything: false) == [
                .selectAll, .share, .deleteSelected,
            ])
        #expect(
            FolderMoreScreen.selectActions(hasEverything: true) == [
                .deselectAll, .share, .deleteSelected,
            ])
        #expect(FolderMoreScreen.isDisabled(.deleteSelected, selectedCount: 0))
        #expect(FolderMoreScreen.isDisabled(.share, selectedCount: 0))
        #expect(!FolderMoreScreen.isDisabled(.deleteSelected, selectedCount: 1))
        #expect(!FolderMoreScreen.isDisabled(.share, selectedCount: 1))
        #expect(!FolderMoreScreen.isDisabled(.selectAll, selectedCount: 0))
        #expect(
            FolderMoreScreen.deleteActions(isRoot: false, selecting: false) == [.delete, .trash])
        #expect(FolderMoreScreen.deleteActions(isRoot: false, selecting: true) == [.trash])
        #expect(FolderMoreScreen.deleteActions(isRoot: true, selecting: false) == [.trash])
        #expect(FolderMoreScreen.sharesFolder(isRoot: false, selecting: false))
        #expect(!FolderMoreScreen.sharesFolder(isRoot: false, selecting: true))
        #expect(!FolderMoreScreen.sharesFolder(isRoot: true, selecting: false))
    }

    /// Add's items, and the bin's buttons and icons.
    @Test func addAndBinSymbols() {
        #expect(AddScreen.items.map(\.kind) == [.session, .folder, .file])
        let buttons = BinScreen.buttons(selecting: false)
        #expect(buttons.map(\.title.key) == ["Select", "More"])
        #expect(buttons.map(\.action) == [.select, nil])
        #expect(buttons.map(\.route) == [.bin, .binMore])
        let selecting = BinScreen.buttons(selecting: true)
        #expect(selecting.map(\.title.key) == ["Done", "More"])
        #expect(selecting.map(\.systemImage) == ["checkmark", "ellipsis.circle"])
        #expect(selecting.map(\.action) == [.done, nil])
        for name in [
            "folder", "document", "checkmark.circle.badge.plus", BinSymbol.restore,
            "rectangle.and.pencil.and.ellipsis", "trash", "trash.fill",
        ] {
            #expect(UIImage(systemName: name) != nil, "\(name)")
        }
        #expect(UIImage(named: FileSymbol.deletePermanently.name) != nil)
        #expect(UIImage(named: "session") != nil)
    }

    @Test func dateStyles() {
        #expect(DateStyle.allCases.map(\.title.key) == ["System", "ISO"])
        #expect(DateStyle.allCases.map(\.rawValue) == ["system", "iso"])
    }
}
