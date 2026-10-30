import Synchronization

/// A continuation that resumes once: with whatever comes first of a reply, an
/// error and a timeout, the others being ignored.
final class OneShot<Value: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Value, any Error>?>

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = Mutex(continuation)
    }

    func finish(_ result: Result<Value, any Error>) {
        let waiting = continuation.withLock { held -> CheckedContinuation<Value, any Error>? in
            defer { held = nil }
            return held
        }
        waiting?.resume(with: result)
    }
}
