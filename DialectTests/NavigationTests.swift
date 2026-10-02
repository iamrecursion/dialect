import Testing
import UIKit

@testable import Dialect

/// The spec's tables: titles, SF Symbols and destinations, in order.
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
            (.files, "Files"), (.editorSettings, "Editor"), (.sessionSettings, "Sessions"),
            (.runtimeSettings, "Runtime"),
            (.companionSettings, "Companion"), (.downloader, "Downloader"),
            (.fileSettings, "Files"), (.downloaderSettings, "Downloader"),
        ]
        for (route, title) in expected {
            #expect(route.placeholderTitle?.key == title)
        }
        #expect(Route.newREPL.placeholderTitle == nil)
        #expect(Route.settings.placeholderTitle == nil)
        #expect(Route.credits.placeholderTitle == nil)
        #expect(Route.appearanceSettings.placeholderTitle == nil)
        #expect(Route.accentColor.placeholderTitle == nil)
    }

    @Test func appearanceRows() {
        #expect(AppearanceView.rows.map(\.title.key) == ["Accent Color"])
        #expect(AppearanceView.rows.map(\.systemImage) == ["swatchpalette"])
        #expect(AppearanceView.rows.map(\.route) == [.accentColor])
        #expect(UIImage(systemName: "swatchpalette") != nil)
    }
}
