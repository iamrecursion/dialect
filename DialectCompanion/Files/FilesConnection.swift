import Foundation
import Synchronization
import WatchConnectivity

/// Asks the watch's Files.
protocol FilesConnection: Sendable {
    func send(_ request: FilesRequest) async throws -> FilesReply
}

enum FilesConnectionError: Error, Equatable {
    /// The request by message wasn't answered in time.
    case timedOut

    /// The request by user info wasn't answered in time, or wasn't sent as the
    /// session isn't ready or the watch hasn't been reachable lately: the watch
    /// is away.
    case noAnswer
}

/// What `LiveFilesConnection` needs of the session, so tests can stand in for
/// it.
protocol FilesSession: AnyObject {
    var isActivated: Bool { get }
    var isReachable: Bool { get }

    /// Both handlers are called off the main actor.
    func sendData(
        _ data: Data, reply: @escaping @Sendable (Data) -> Void,
        failed: @escaping @Sendable (any Error) -> Void)
    func sendInfo(_ info: [String: Any]) -> any FilesInfoTransfer
}

/// A queued user info, which can be taken back until it's delivered.
protocol FilesInfoTransfer: AnyObject {
    func cancel()
}

extension WCSessionUserInfoTransfer: FilesInfoTransfer {}

extension WCSession: FilesSession {
    var isActivated: Bool { activationState == .activated }

    func sendData(
        _ data: Data, reply: @escaping @Sendable (Data) -> Void,
        failed: @escaping @Sendable (any Error) -> Void
    ) {
        sendMessageData(data, replyHandler: reply, errorHandler: failed)
    }

    func sendInfo(_ info: [String: Any]) -> any FilesInfoTransfer {
        return transferUserInfo(info)
    }
}

/// Asks by the fastest way there is: by message while the watch is reachable,
/// otherwise by user info, which a dimmed Dialect answers for its first few
/// seconds. After that, Dialect is suspended and the watch isn't asked.
///
/// Unchecked, as what it holds of the session is safe from any thread, and its
/// own state is behind the lock. Nothing here is isolated to the main actor, as
/// WatchConnectivity calls the handlers on its own queue.
final class LiveFilesConnection: FilesConnection, @unchecked Sendable {
    private let session: any FilesSession
    private let messageTimeout: Duration
    private let answerWait: Duration

    /// How long after the watch was last reachable it's asked by user info.
    private let dimmedWindow: Duration

    /// Those waiting for an answer by user info, by the request's ID.
    private let waiting = Mutex<[String: OneShot<Data>]>([:])
    private let reach = Mutex(Reach())

    /// Whether the session last said the watch was reachable, and when it
    /// stopped being so.
    private struct Reach {
        var isReachable = false
        var ended: ContinuousClock.Instant?
    }

    init(
        session: any FilesSession, messageTimeout: Duration = .seconds(15),
        answerWait: Duration = .seconds(3), dimmedWindow: Duration = .seconds(10)
    ) {
        self.session = session
        self.messageTimeout = messageTimeout
        self.answerWait = answerWait
        self.dimmedWindow = dimmedWindow
    }

    func send(_ request: FilesRequest) async throws -> FilesReply {
        guard session.isActivated else { throw FilesConnectionError.noAnswer }
        let data = try FilesCoding.encode(request)
        let answer: Data
        if session.isReachable {
            do {
                answer = try await byMessage(data)
            } catch  where !session.isReachable {
                // The wrist came down in the meantime, and a dimmed Dialect can still answer.
                answer = try await byUserInfo(data)
            }
        } else {
            answer = try await byUserInfo(data)
        }
        return try FilesCoding.decode(FilesReply.self, from: answer)
    }

    /// An answer by user info, from the session's delegate. A late one finds
    /// nobody waiting.
    func deliver(_ answer: FilesUserInfo) {
        take(answer.id)?.finish(.success(answer.data))
    }

    /// Whether the watch is reachable, each time the session says.
    func reachabilityChanged(_ reachable: Bool) {
        reach.withLock { reach in
            if reach.isReachable, !reachable { reach.ended = .now }
            reach.isReachable = reachable
        }
    }

    private var wasReachableLately: Bool {
        return reach.withLock { reach in
            guard !reach.isReachable else { return true }
            guard let ended = reach.ended else { return false }
            return .now - ended <= dimmedWindow
        }
    }

    private func take(_ id: String) -> OneShot<Data>? {
        return waiting.withLock { $0.removeValue(forKey: id) }
    }

    private func byMessage(_ data: Data) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let answer = OneShot<Data>(continuation)
            session.sendData(
                data, reply: { answer.finish(.success($0)) },
                failed: { answer.finish(.failure($0)) })
            Task { [messageTimeout] in
                try? await Task.sleep(for: messageTimeout)
                answer.finish(.failure(FilesConnectionError.timedOut))
            }
        }
    }

    private func byUserInfo(_ data: Data) async throws -> Data {
        guard wasReachableLately else { throw FilesConnectionError.noAnswer }
        let id = UUID().uuidString
        let info = FilesUserInfo(id: id, data: data, sent: Date())
        return try await withCheckedThrowingContinuation { continuation in
            let answer = OneShot<Data>(continuation)
            waiting.withLock { $0[id] = answer }
            nonisolated(unsafe) let transfer = session.sendInfo(info.propertyList)
            Task { [answerWait] in
                try? await Task.sleep(for: answerWait)
                guard let unanswered = self.take(id) else { return }
                transfer.cancel()
                unanswered.finish(.failure(FilesConnectionError.noAnswer))
            }
        }
    }
}
