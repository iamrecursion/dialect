import SwiftUI

/// Where what a screen of Files shows came from.
enum BrowsingState: Equatable, Sendable {
    case loading

    /// Just heard from the watch.
    case live

    /// From the cache, of what the watch said at this time.
    case cached(Date)

    /// The watch isn't answering, and has never shown this.
    case neverSeen
    case missing
    case failed(String)

    /// The Watch tab says why.
    case unavailable

    /// What a screen's "last seen" is of.
    enum Seen {
        case folder, trash, recents
    }

    /// "Folder last seen *when*", or the Trash's or Recents', under the title
    /// of a screen showing the cache.
    func subtitle(of seen: Seen, now: Date) -> String {
        guard case .cached(let date) = self else { return "" }
        let when = LastSeen.phrase(for: now.timeIntervalSince(date))
        switch seen {
        case .folder: return String(localized: "Folder last seen \(when)")
        case .trash: return String(localized: "Trash last seen \(when)")
        case .recents: return String(localized: "Recents last seen \(when)")
        }
    }
}

/// What a screen knows of how its last read went.
struct BrowsingStatus {
    private(set) var state = BrowsingState.loading

    /// When the watch last said what the screen shows.
    private(set) var seen: Date?
    private(set) var lastRequestFailed = false

    /// Shows what the cache holds. The state waits for what the watch says.
    mutating func showCache(seen: Date) {
        self.seen = seen
    }

    mutating func heard(at date: Date = Date()) {
        seen = date
        lastRequestFailed = false
        state = .live
    }

    mutating func noAnswer() {
        lastRequestFailed = true
        state = seen.map(BrowsingState.cached) ?? .neverSeen
    }

    mutating func failed(_ reason: String) {
        lastRequestFailed = true
        state = seen.map(BrowsingState.cached) ?? .failed(reason)
    }

    mutating func missing() {
        seen = nil
        lastRequestFailed = false
        state = .missing
    }

    mutating func set(_ state: BrowsingState) {
        self.state = state
    }

    mutating func connectionEnded() {
        if state == .live, let seen { state = .cached(seen) }
    }

    /// For another Dialect, whose files these aren't.
    mutating func reset() {
        self = BrowsingStatus()
    }
}

/// A screen of Files, which hears of the connection while it's on top.
@MainActor
protocol BrowsingModel: AnyObject {
    var status: BrowsingStatus { get set }

    /// Which read is the latest; earlier ones stop when they hear back.
    var reads: Int { get set }

    func refresh() async

    /// Drops what it shows, which was of another Dialect.
    func reset()
}

extension BrowsingModel {
    var state: BrowsingState { status.state }

    /// Whether its last request failed, so it should ask again.
    var lastRequestFailed: Bool { status.lastRequestFailed }

    func connectionEnded() {
        status.connectionEnded()
    }

    /// Stops what's being read, as the screen has left.
    func leave() {
        reads += 1
    }

    /// Whether the watch can be asked, saying so if not.
    func canAsk(_ files: WatchFiles) -> Bool {
        if files.canAsk { return true }
        status.set(files.link.status == nil ? .loading : .unavailable)
        return false
    }
}

extension View {
    /// Reads `model` each time the screen appears, and tells `files` it's on
    /// top.
    func browsing(_ model: any BrowsingModel, files: WatchFiles) -> some View {
        return
            onAppear {
                files.showing(model)
                Task { await files.refresh(model) }
            }
            .onDisappear { model.leave() }
    }
}
