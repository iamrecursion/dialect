import Foundation
import Testing

@testable import Dialect

/// Settings › Files: defaults, Text Extensions' checks, and the extensions last
/// used to make a file.
struct FileSettingsTests {
    /// A fresh, empty store of settings, removed when the test is done.
    private final class Defaults {
        let name = "FileSettingsTests-\(UUID().uuidString)"
        let defaults: UserDefaults

        init() {
            defaults = UserDefaults(suiteName: name)!
        }

        deinit {
            defaults.removePersistentDomain(forName: name)
        }
    }

    @Test func defaults() {
        let store = Defaults()
        #expect(FileSettings.confirmExtensionChangesDefault)
        #expect(FileSettings.emptyTrashAfter(in: store.defaults) == 30)
        #expect(FileSettings.recentExtensions(in: store.defaults).isEmpty)
    }

    /// 0 days is Never.
    @Test func emptyTrashAfterNever() {
        let store = Defaults()
        store.defaults.set(0, forKey: FileSettings.emptyTrashAfterKey)
        #expect(FileSettings.emptyTrashAfter(in: store.defaults) == nil)
        store.defaults.set(7, forKey: FileSettings.emptyTrashAfterKey)
        #expect(FileSettings.emptyTrashAfter(in: store.defaults) == 7)
        // As a launch argument gives it.
        store.defaults.set("1", forKey: FileSettings.emptyTrashAfterKey)
        #expect(FileSettings.emptyTrashAfter(in: store.defaults) == 1)
    }

    @Test func offersTheSpecsChoicesOfDays() {
        #expect(FileSettings.emptyTrashAfterChoices == [0, 1, 3, 7, 14, 30, 90])
        #expect(FileSettings.emptyTrashAfterTitle(0) == "Never")
        #expect(FileSettings.emptyTrashAfterTitle(1) == "1 Day")
        #expect(FileSettings.emptyTrashAfterTitle(30) == "30 Days")
    }

    @Test func remembersTheExtensionsUsedMostRecentFirst() {
        let store = Defaults()
        FileSettings.recordExtension("md", in: store.defaults)
        FileSettings.recordExtension("txt", in: store.defaults)
        FileSettings.recordExtension("md", in: store.defaults)
        #expect(FileSettings.recentExtensions(in: store.defaults) == ["md", "txt"])
    }

    // MARK: Text Extensions

    private func problem(_ typed: String, _ existing: [String] = []) -> TextExtensionProblem? {
        return FileSettings.textExtensionProblem(typed, existing: existing)
    }

    /// Stored without the dot, in lowercase.
    @Test func storesAnExtensionPlainly() {
        #expect(FileSettings.normalizedExtension(".RKT") == "rkt")
        #expect(FileSettings.normalizedExtension("  el ") == "el")
        #expect(problem(".RKT") == nil)
    }

    @Test func refusesAnEmptyExtension() {
        #expect(problem("") == .empty)
        #expect(problem(".") == .empty)
        #expect(problem("  ") == .empty)
    }

    @Test func refusesASlashOrADot() {
        #expect(problem("a/b") == .slash)
        #expect(problem("tar.gz") == .dot)
    }

    @Test func refusesAnExtensionAlreadyListed() {
        #expect(problem(".EL", ["el"]) == .listed("el"))
        #expect(problem("el", [".El"]) == .listed("el"))
    }

    /// An extension Files already knows is refused: adding it would do nothing,
    /// or change its kind.
    @Test func refusesAnExtensionFilesKnows() {
        #expect(problem("png") == .known("png", .image))
        #expect(problem("MD") == .known("md", .text))
        #expect(problem("scm") == .known("scm", .scheme))
        #expect(problem("mov") == .known("mov", .video))
    }

    @Test func givesEachRefusalAReason() {
        #expect(
            TextExtensionProblem.known("png", .image).reason
                == "Files already treats .png as an image.")
        #expect(
            TextExtensionProblem.known("md", .text).reason == "Files already treats .md as text.")
        #expect(TextExtensionProblem.listed("el").reason.contains(".el"))
        for problem: TextExtensionProblem in [.empty, .slash, .dot] {
            #expect(!problem.reason.isEmpty)
        }
    }
}
