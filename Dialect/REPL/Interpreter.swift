import Foundation
import LispKit

/// The result of evaluating one line entered at the REPL.
struct Evaluation: Equatable, Sendable {
    var output: String
    var result: Outcome

    enum Outcome: Equatable, Sendable {
        /// A value, written as Scheme writes it.
        case value(String)

        /// Nothing worth showing, such as a definition's result.
        case none

        /// An error message back from the REPL.
        case error(String)
    }
}

/// Dialect's Scheme interpreter: one LispKit context on its own thread.
///
/// This is the one file that touches LispKit. Its types are not `Sendable` and
/// the context is not thread-safe, so the context is created, used and dropped
/// only on the interpreter's thread, and only `String`s cross to and from it:
/// hence `@unchecked Sendable`.
///
/// The thread has a large stack: Swift frees a LispKit list recursively, so
/// dropping a long list needs one. The context boots when initialized.
final class Interpreter: @unchecked Sendable {
    private static let stackSize = 12 * 1024 * 1024

    private let condition = NSCondition()
    /// Work for the thread, guarded by `condition`.
    private var jobs: [() -> Void] = []
    private var stopping = false

    /// Created on the interpreter's thread, by the first entry.
    private var context: LispKitContext?
    private let delegate = OutputCollector()

    init() {
        let thread = Thread { [self] in run() }
        thread.stackSize = Self.stackSize
        thread.name = "Dialect interpreter"
        thread.start()
    }

    /// Boots the context now, so the first entry doesn't wait for it; returns
    /// whether Scheme started. Booting twice is a no-op.
    func warmUp() async -> Bool {
        return await withCheckedContinuation { continuation in
            enqueue { [self] in continuation.resume(returning: bootIfNeeded() != nil) }
        }
    }

    /// Evaluates one entry, which may hold several expressions, and returns the
    /// last one's result.
    func evaluate(_ text: String) async -> Evaluation {
        return await withCheckedContinuation { continuation in
            enqueue { [self] in continuation.resume(returning: evaluateHere(text)) }
        }
    }

    /// Ends the thread once any entry in progress has finished; the context
    /// goes with it.
    func stop() {
        condition.lock()
        stopping = true
        condition.signal()
        condition.unlock()
    }

    private func enqueue(_ job: @escaping () -> Void) {
        condition.lock()
        jobs.append(job)
        condition.signal()
        condition.unlock()
    }

    /// The thread's loop.
    private func run() {
        while true {
            condition.lock()
            while jobs.isEmpty && !stopping { condition.wait() }
            if jobs.isEmpty {
                condition.unlock()
                break
            }
            let job = jobs.removeFirst()
            condition.unlock()
            job()
        }
        context = nil
    }

    // Everything below runs on the interpreter's thread.

    private func evaluateHere(_ text: String) -> Evaluation {
        delegate.output = ""
        guard let context = bootIfNeeded() else {
            return Evaluation(output: "", result: .error("Scheme could not start."))
        }
        let result = context.evaluator.execute { machine in
            try machine.eval(
                str: text, sourceId: SourceManager.consoleSourceId, in: context.global, as: "<repl>"
            )
        }
        return Evaluation(output: delegate.output, result: Self.outcome(of: result))
    }

    private func bootIfNeeded() -> LispKitContext? {
        if let context { return context }
        let context = LispKitContext(
            delegate: delegate, implementationName: "Dialect", implementationVersion: "0.1",
            commandLineArguments: [], includeInternalResources: false, includeDocumentPath: nil)
        guard context.usePackageResources(), let prelude = LispKitContext.packagePreludePath else {
            return nil
        }
        do {
            try context.bootstrap()
            _ = try context.evaluator.machine.eval(file: prelude, in: context.global)
        } catch {
            return nil
        }
        self.context = context
        return context
    }

    private static func outcome(of result: Expr) -> Evaluation.Outcome {
        switch result {
        case .void: return .none
        case .error(let error): return .error(error.message)
        default: return .value(result.description)
        }
    }
}

/// Collects what Scheme prints. Reading input is not supported yet.
private final class OutputCollector: ContextDelegate {
    var output = ""

    func print(_ str: String) {
        output += str
    }

    func read() -> String? {
        return nil
    }
}
