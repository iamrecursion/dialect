import Foundation
import Synchronization
import Testing

@testable import DialectCompanion

/// Asking the watch: by message or by user info, each answered once, however
/// late or often what comes back arrives.
struct LiveFilesConnectionTests {
    /// Stands in for the session, keeping what's sent for the test to answer.
    private final class Session: FilesSession, @unchecked Sendable {
        var isActivated = true
        var isReachable = true
        let replies = Mutex<[@Sendable (Data) -> Void]>([])
        let failures = Mutex<[@Sendable (any Error) -> Void]>([])
        let infos = Mutex<[FilesUserInfo]>([])
        let cancelled = Mutex(0)

        final class Transfer: FilesInfoTransfer {
            let session: Session

            init(session: Session) {
                self.session = session
            }

            func cancel() {
                session.cancelled.withLock { $0 += 1 }
            }
        }

        func sendData(
            _ data: Data, reply: @escaping @Sendable (Data) -> Void,
            failed: @escaping @Sendable (any Error) -> Void
        ) {
            replies.withLock { $0.append(reply) }
            failures.withLock { $0.append(failed) }
        }

        func sendInfo(_ info: [String: Any]) -> any FilesInfoTransfer {
            if let request = FilesUserInfo(request: info) {
                infos.withLock { $0.append(request) }
            }
            return Transfer(session: self)
        }

        func answerMessage(_ reply: FilesReply) throws {
            let data = try FilesCoding.encode(reply)
            replies.withLock { $0.first }?(data)
        }

        func failMessage() {
            failures.withLock { $0.first }?(CocoaError(.fileLocking))
        }

        /// Waits for something to have been sent.
        func waitForSend() async {
            for _ in 0..<500 {
                if !replies.withLock({ $0.isEmpty }) || !infos.withLock({ $0.isEmpty }) { return }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        func waitForInfo() async -> FilesUserInfo {
            while true {
                if let info = firstInfo { return info }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        var firstInfo: FilesUserInfo? {
            return infos.withLock { $0.first }
        }
    }

    private let session = Session()
    private let request = FilesRequest(body: .recents)
    private let reply = FilesReply.failed("from the watch")

    /// One that has heard the watch is reachable.
    private func connection(
        timeout: Duration = .seconds(10), wait: Duration = .seconds(10),
        window: Duration = .seconds(10)
    ) -> LiveFilesConnection {
        let connection = LiveFilesConnection(
            session: session, messageTimeout: timeout, answerWait: wait, dimmedWindow: window)
        connection.reachabilityChanged(true)
        return connection
    }

    private func lowerWrist(_ connection: LiveFilesConnection) {
        session.isReachable = false
        connection.reachabilityChanged(false)
    }

    // MARK: By message

    @Test func anAnsweredMessageGivesItsReply() async throws {
        let connection = connection()
        let asking = Task { try await connection.send(request) }
        await session.waitForSend()
        try session.answerMessage(reply)
        #expect(try await asking.value == reply)
    }

    @Test func aStalledMessageFailsAtTheTimeout() async {
        let connection = connection(timeout: .milliseconds(50))
        await #expect(throws: FilesConnectionError.timedOut) {
            try await connection.send(request)
        }
    }

    @Test func aLateReplyChangesNothing() async throws {
        let connection = connection(timeout: .milliseconds(50))
        await #expect(throws: FilesConnectionError.timedOut) {
            try await connection.send(request)
        }
        try session.answerMessage(reply)
        session.failMessage()
    }

    @Test func anErrorAfterAReplyChangesNothing() async throws {
        let connection = connection(timeout: .milliseconds(50))
        let asking = Task { try await connection.send(request) }
        await session.waitForSend()
        try session.answerMessage(reply)
        session.failMessage()
        #expect(try await asking.value == reply)
        // The timeout passes too.
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test func aFailedMessageThrows() async {
        let connection = connection()
        let asking = Task { try await connection.send(request) }
        await session.waitForSend()
        session.failMessage()
        await #expect(throws: CocoaError.self) { try await asking.value }
    }

    /// The wrist came down while a message was on its way.
    @Test func aFailedMessageGoesByUserInfoOnceNotReachable() async throws {
        let connection = connection()
        let asking = Task { try await connection.send(request) }
        await session.waitForSend()
        lowerWrist(connection)
        session.failMessage()
        let sent = await session.waitForInfo()
        connection.deliver(
            FilesUserInfo(id: sent.id, data: try FilesCoding.encode(reply), sent: nil))
        #expect(try await asking.value == reply)
    }

    // MARK: By user info

    @Test func goesByUserInfoWhenNotReachable() async throws {
        let connection = connection()
        lowerWrist(connection)
        let asking = Task { try await connection.send(request) }
        await session.waitForSend()
        let sent = try #require(session.firstInfo)
        #expect(session.replies.withLock { $0.isEmpty })
        #expect(sent.sent != nil)

        let answer = FilesUserInfo(id: sent.id, data: try FilesCoding.encode(reply), sent: nil)
        connection.deliver(try #require(FilesUserInfo(answer: answer.propertyList)))
        #expect(try await asking.value == reply)
        #expect(session.cancelled.withLock { $0 } == 0)
    }

    @Test func noAnswerCancelsTheTransferAndIgnoresALateOne() async throws {
        let connection = connection(wait: .milliseconds(50))
        lowerWrist(connection)
        await #expect(throws: FilesConnectionError.noAnswer) {
            try await connection.send(request)
        }
        #expect(session.cancelled.withLock { $0 } == 1)

        let sent = try #require(session.firstInfo)
        connection.deliver(FilesUserInfo(id: sent.id, data: Data(), sent: nil))
    }

    @Test func anotherRequestsAnswerIsIgnored() async throws {
        let connection = connection(wait: .milliseconds(100))
        lowerWrist(connection)
        let asking = Task { try await connection.send(request) }
        await session.waitForSend()
        connection.deliver(
            FilesUserInfo(id: "someone else", data: try FilesCoding.encode(reply), sent: nil))
        await #expect(throws: FilesConnectionError.noAnswer) { try await asking.value }
    }

    /// The wait carries on as it began; the answer may yet come by user info.
    @Test func goingReachableMidWaitIsSafe() async throws {
        let connection = connection()
        lowerWrist(connection)
        let asking = Task { try await connection.send(request) }
        await session.waitForSend()
        session.isReachable = true
        connection.reachabilityChanged(true)
        let sent = try #require(session.firstInfo)
        connection.deliver(
            FilesUserInfo(id: sent.id, data: try FilesCoding.encode(reply), sent: nil))
        #expect(try await asking.value == reply)
    }

    /// Dialect is suspended by then, and would see the request only once it's
    /// stale.
    @Test func aWatchDimmedAWhileIsNotAsked() async throws {
        let connection = connection(window: .milliseconds(50))
        lowerWrist(connection)
        try await Task.sleep(for: .milliseconds(100))
        // Saying again that it's out of reach doesn't start the window over.
        connection.reachabilityChanged(false)
        await #expect(throws: FilesConnectionError.noAnswer) {
            try await connection.send(request)
        }
        #expect(session.infos.withLock { $0.isEmpty })

        connection.reachabilityChanged(true)
        lowerWrist(connection)
        let asking = Task { try await connection.send(request) }
        let sent = await session.waitForInfo()
        connection.deliver(
            FilesUserInfo(id: sent.id, data: try FilesCoding.encode(reply), sent: nil))
        #expect(try await asking.value == reply)
    }

    @Test func aWatchNeverReachableIsNotAsked() async {
        session.isReachable = false
        let connection = LiveFilesConnection(session: session)
        await #expect(throws: FilesConnectionError.noAnswer) {
            try await connection.send(request)
        }
        #expect(session.infos.withLock { $0.isEmpty })
    }

    @Test func aSessionNotYetActiveGivesNoAnswer() async {
        session.isActivated = false
        session.isReachable = false
        let connection = connection()
        await #expect(throws: FilesConnectionError.noAnswer) {
            try await connection.send(request)
        }
        #expect(session.infos.withLock { $0.isEmpty })
    }

    @Test func anUnreadableAnswerThrows() async throws {
        let connection = connection()
        let asking = Task { try await connection.send(request) }
        await session.waitForSend()
        session.replies.withLock { $0.first }?(Data("nope".utf8))
        await #expect(throws: (any Error).self) { try await asking.value }
    }

    // MARK: The link

    @MainActor
    @Test func theLinkHoldsTheWatchDirectory() {
        let link = PhoneLink()
        #expect(link.watchDirectory == nil)
        let facts = LinkFacts(
            isPaired: true, isWatchAppInstalled: true, isReachable: true, snapshot: .none)
        let directory = URL(filePath: "/tmp/watch")
        link.update(facts, snapshot: nil, edits: nil, watchDirectory: directory)
        #expect(link.watchDirectory == directory)
        link.update(facts, snapshot: nil, edits: nil, watchDirectory: nil)
        #expect(link.watchDirectory == nil)
    }
}
