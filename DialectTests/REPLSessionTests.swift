import Testing

@testable import Dialect

/// A REPL's transcript: what was entered, and what each entry gave.
@MainActor
@Suite(.serialized)
struct REPLSessionTests {
    @Test func recordsAnEntryAndItsResult() async {
        let session = REPLSession()
        defer { session.close() }
        session.draft = "  (+ 1 2) "
        await session.submit()
        #expect(session.draft == "")
        #expect(session.entries.map(\.input) == ["(+ 1 2)"])
        #expect(session.entries.first?.evaluation?.result == .value("3"))
    }

    /// A mistake stays in the field to be fixed (Starfire): only a success
    /// clears it.
    @Test func keepsAnEntryThatFailed() async {
        let session = REPLSession()
        defer { session.close() }
        session.draft = "(car 1)"
        await session.submit()
        #expect(session.draft == "(car 1)")
        #expect(session.entries.count == 1)
    }

    /// SwiftUI can make a view's initial state more than once and keep only the
    /// first: a session must not start an interpreter (a thread, then a booted
    /// context) just by existing.
    @Test func startsNoInterpreterUntilAsked() {
        let session = REPLSession()
        #expect(!session.isStarted)
    }

    @Test func startsItsInterpreterWhenAsked() async {
        let session = REPLSession()
        defer { session.close() }
        #expect(await session.start())
        #expect(session.isStarted)
    }

    @Test func ignoresABlankEntry() async {
        let session = REPLSession()
        defer { session.close() }
        session.draft = "   "
        await session.submit()
        #expect(session.entries.isEmpty)
    }
}
