import Foundation
import Observation

/// One REPL: its transcript and its interpreter, which boots on the first
/// entry.
@MainActor
@Observable
final class REPLSession {
    struct Entry: Identifiable {
        let id = UUID()
        let input: String
        /// `nil` while it is being evaluated.
        var evaluation: Evaluation?
    }

    private(set) var entries: [Entry] = []
    /// What is being typed.
    var draft = ""

    /// Made when the session starts or is first used, not with the session:
    /// SwiftUI can make a view's initial state more than once and keep only the
    /// first, and each interpreter is a thread and, once booted, a context.
    private var interpreter: Interpreter?

    var isStarted: Bool { interpreter != nil }

    /// Starts the interpreter and boots Scheme, so the first entry does not
    /// wait for it.
    @discardableResult
    func start() async -> Bool {
        return await running().warmUp()
    }

    /// Evaluates the draft, if it is not blank, and records it and its result.
    func submit() async {
        let submitted = draft
        let input = submitted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let entry = Entry(input: input)
        entries.append(entry)
        let evaluation = await running().evaluate(input)
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].evaluation = evaluation
        }
        if case .error = evaluation.result { return }
        if draft == submitted { draft = "" }
    }

    /// Ends the interpreter; the session cannot evaluate after this.
    func close() {
        interpreter?.stop()
    }

    private func running() -> Interpreter {
        if let interpreter { return interpreter }
        let interpreter = Interpreter()
        self.interpreter = interpreter
        return interpreter
    }
}
