import Foundation
import Testing
import UIKit

@testable import Dialect

/// The clipboard's screens: the order clashes are asked in, and what they say.
struct ClipboardScreenTests {
    private let clashes = ["a.txt", "b.txt", "c.txt"].map {
        Clash(source: FilePath("notes/\($0)"), existing: $0, canReplace: true)
    }

    @Test func asksAboutEachClashInTurn() {
        var queue = ClashQueue(clashes)
        #expect(queue.current == clashes[0])
        #expect(queue.remaining == 3)
        queue.answer(.skip, toAll: false)
        #expect(queue.current == clashes[1])
        #expect(queue.remaining == 2)
        queue.answer(.replace, toAll: false)
        queue.answer(.keepBoth, toAll: false)
        #expect(queue.current == nil)
        #expect(
            queue.choices == [
                FilePath("notes/a.txt"): .skip, FilePath("notes/b.txt"): .replace,
                FilePath("notes/c.txt"): .keepBoth,
            ])
    }

    /// Apply to All answers the current clash and every one after it.
    @Test func appliesAnAnswerToTheRest() {
        var queue = ClashQueue(clashes)
        queue.answer(.skip, toAll: false)
        queue.answer(.replace, toAll: true)
        #expect(queue.current == nil)
        #expect(queue.remaining == 0)
        #expect(
            queue.choices == [
                FilePath("notes/a.txt"): .skip, FilePath("notes/b.txt"): .replace,
                FilePath("notes/c.txt"): .replace,
            ])
    }

    @Test func hasNothingToAskWithoutClashes() {
        var queue = ClashQueue([])
        #expect(queue.current == nil)
        queue.answer(.skip, toAll: true)
        #expect(queue.choices.isEmpty)
    }

    @Test func saysWhatClashes() {
        #expect(
            ClashScreen.title(existing: "todo.txt", folder: FilePath("notes"))
                == "An item named todo.txt already exists in notes.")
        #expect(
            ClashScreen.title(existing: "todo.txt", folder: .root)
                == "An item named todo.txt already exists in Files.")
    }

    @Test func saysHowFarItGot() {
        #expect(
            Transfer.Kind.paste.stoppedNote(placed: 1, reason: "No space.")
                == "1 item was pasted before Paste stopped. No space.")
        #expect(
            Transfer.Kind.move.stoppedNote(placed: 2, reason: "No space.")
                == "2 items were moved before Move stopped. No space.")
    }

    @Test func headsTheItemsWithTheirFolder() {
        #expect(ClipboardScreen.heading(for: .root) == "In Files")
        #expect(ClipboardScreen.heading(for: FilePath("notes/old")) == "In /notes/old")
    }

    @Test func everySymbolExists() {
        for symbol in [
            ClipboardSymbol.copy, ClipboardSymbol.paste, ClipboardSymbol.move,
            ClipboardSymbol.clear,
        ] {
            #expect(UIImage(systemName: symbol) != nil, "\(symbol)")
        }
    }
}
