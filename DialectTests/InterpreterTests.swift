import Testing

@testable import Dialect

/// The interpreter, booted for real in the test host. One per test, stopped
/// afterwards.
@Suite(.serialized)
struct InterpreterTests {
    @Test func evaluatesAnExpression() async {
        let interpreter = Interpreter()
        defer { interpreter.stop() }
        #expect(
            await interpreter.evaluate("(+ 1 2)") == Evaluation(output: "", result: .value("3")))
    }

    /// Booting ahead of the first entry, as the REPL does when its screen
    /// opens.
    @Test func warmsUp() async {
        let interpreter = Interpreter()
        defer { interpreter.stop() }
        #expect(await interpreter.warmUp())
        #expect(await interpreter.warmUp(), "a second warm-up is a no-op")
        #expect(await interpreter.evaluate("(+ 1 2)").result == .value("3"))
    }

    @Test func keepsDefinitionsFromOneEntryToTheNext() async {
        let interpreter = Interpreter()
        defer { interpreter.stop() }
        // LispKit's `define` returns the symbol it defined, as its REPL shows.
        #expect(await interpreter.evaluate("(define x 41)").result == .value("x"))
        #expect(await interpreter.evaluate("(+ x 1)").result == .value("42"))
    }

    /// Libraries come from LispKit's bundle in the app: SRFIs and LispKit's
    /// own.
    @Test func importsLibraries() async {
        let interpreter = Interpreter()
        defer { interpreter.stop() }
        let imported = await interpreter.evaluate("(import (srfi 1))").result
        #expect(!Self.isError(imported), "\(imported)")
        #expect(await interpreter.evaluate("(iota 3)").result == .value("(0 1 2)"))
        let lispkit = await interpreter.evaluate("(import (lispkit json))").result
        #expect(!Self.isError(lispkit), "\(lispkit)")
    }

    private static func isError(_ outcome: Evaluation.Outcome) -> Bool {
        if case .error = outcome { return true }
        return false
    }

    @Test func capturesWhatIsDisplayed() async {
        let interpreter = Interpreter()
        defer { interpreter.stop() }
        #expect(
            await interpreter.evaluate("(display \"hello\")")
                == Evaluation(output: "hello", result: .none))
    }

    @Test func reportsErrors() async {
        let interpreter = Interpreter()
        defer { interpreter.stop() }
        guard case .error(let message) = await interpreter.evaluate("(car 1)").result else {
            Issue.record("(car 1) did not fail")
            return
        }
        #expect(!message.isEmpty)
    }
}
