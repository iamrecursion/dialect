#if DEBUG
    import Foundation
    import Synchronization

    /// Stands in for the watch's answers, for tests and `-fakeWatch`.
    final class FakeFilesConnection: FilesConnection {
        typealias Handler = @Sendable (FilesRequest.Body) async throws -> FilesReply

        private let handler: Handler
        private let asked = Mutex<[FilesRequest.Body]>([])

        init(handler: @escaping Handler) {
            self.handler = handler
        }

        /// Every request so far, in order.
        var requests: [FilesRequest.Body] { asked.withLock { $0 } }

        func send(_ request: FilesRequest) async throws -> FilesReply {
            asked.withLock { $0.append(request.body) }
            return try await handler(request.body)
        }
    }
#endif
