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
            (.clipboard(.root), "Clipboard"),
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
    }

    @Test func appearanceRows() {
        #expect(AppearanceView.rows.map(\.title.key) == ["Accent Color"])
        #expect(AppearanceView.rows.map(\.systemImage) == ["swatchpalette"])
        #expect(AppearanceView.rows.map(\.route) == [.accentColor])
        #expect(UIImage(systemName: "swatchpalette") != nil)
    }

    /// The folder screen's buttons. Clipboard is disabled until it has a
    /// screen.
    @Test func folderButtons() {
        let notes = FilePath(components: ["notes"])
        let buttons = FolderScreen.buttons(for: notes)
        #expect(buttons.map(\.title.key) == ["Add", "Clipboard", "More"])
        #expect(
            buttons.map(\.systemImage) == ["plus.capsule", "list.clipboard", "ellipsis.circle"])
        #expect(buttons.map(\.route) == [.add(notes), .clipboard(notes), .folderMore(notes)])
        #expect(buttons.map(\.isDisabled) == [false, true, false])
        // The clipboard's clip sticks up above its board, which then sits about 1.5 pt low beside
        // its neighbors (measured on the 42 mm and Ultra screenshots).
        #expect(buttons.map(\.opticalOffset) == [0, -1.5, 0])
        for item in buttons {
            #expect(UIImage(systemName: item.systemImage) != nil, "\(item.systemImage)")
        }
    }

    /// A folder's More screen's items, in order.
    @Test func folderMoreItems() {
        #expect(
            FolderMoreScreen.Action.allCases.map(\.systemImage) == [
                "arrow.up.arrow.down", "square.grid.3x1.below.line.grid.1x2", "eye",
                "info.circle", "trash", "trash.fill", "gear",
            ])
        #expect(
            FolderMoreScreen.Action.allCases.map(\.title.key) == [
                "Sort", "Group", "Show Hidden", "Folder Info", "Delete", "Trash", "Settings",
            ])
        for action in FolderMoreScreen.Action.allCases {
            #expect(UIImage(systemName: action.systemImage) != nil, "\(action.systemImage)")
        }
        #expect(UIImage(systemName: "eye.slash") != nil)
        #expect(UIImage(systemName: "info.circle") != nil)
    }

    /// Add's items, and the bin's buttons and icons.
    @Test func addAndBinSymbols() {
        #expect(AddScreen.items.map(\.kind) == [.session, .folder, .file])
        #expect(BinScreen.buttons.map(\.title.key) == ["Select", "More"])
        #expect(BinScreen.buttons.map(\.isDisabled) == [true, false])
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
