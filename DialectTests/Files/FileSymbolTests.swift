import Testing
import UIKit

@testable import Dialect

/// Every icon Files shows exists on watchOS 27: system symbols by name, and
/// Dialect's in its asset catalog.
@MainActor
struct FileSymbolTests {
    @Test func kindsUseTheSpecsIcons() {
        let expected: [(FileKind, FileSymbol)] = [
            (.folder, .system("folder.fill")), (.session, .custom("session")),
            (.scheme, .custom("scheme")), (.text, .system("text.document.fill")),
            (.image, .system("photo.fill")), (.video, .system("video.fill")),
            (.otherText, .system("document.fill")), (.binary, .system("questionmark.app.fill")),
        ]
        for (kind, symbol) in expected {
            #expect(kind.symbol == symbol, "\(kind)")
        }
    }

    @Test(arguments: FileKind.allCases)
    func everyKindsIconLoads(kind: FileKind) {
        switch kind.symbol {
        case .system(let name): #expect(UIImage(systemName: name) != nil, "\(name)")
        case .custom(let name): #expect(UIImage(named: name) != nil, "\(name)")
        }
    }

    /// Delete Permanently's, used by the bin.
    @Test func thePermanentTrashLoads() {
        #expect(UIImage(named: FileSymbol.deletePermanently.name) != nil)
    }

    /// Custom symbols are symbols, so they scale with text like the system's.
    @Test func customSymbolsAreSymbols() throws {
        let session = try #require(UIImage(named: "session"))
        #expect(session.isSymbolImage)
    }
}
