import Foundation
import Observation

/// The watch's settings that shape Files on the phone, from the link, with
/// their defaults while there's no snapshot.
struct FilesDisplay: Equatable, Sendable {
    var showExtensions = FileSettings.showExtensionsDefault
    var showDetails = FileSettings.showDetailsDefault
    var relativeModified = FileSettings.relativeModifiedDefault
    var foldersFirst = FileSettings.foldersFirstDefault
    var showHidden = FileSettings.showHiddenDefault
    var dateStyle = FileSettings.dateStyleDefault
    var use24Hour = FileSettings.use24HourDefault

    /// Days an item stays in the bin; `nil` for Never.
    var emptyTrashAfter: Int? = FileSettings.emptyTrashAfterDefault

    init() {}

    init(value: (String) -> SettingValue?) {
        let defaults = FilesDisplay()
        showExtensions = value(FileSettings.showExtensionsKey)?.bool ?? defaults.showExtensions
        showDetails = value(FileSettings.showDetailsKey)?.bool ?? defaults.showDetails
        relativeModified =
            value(FileSettings.relativeModifiedKey)?.bool ?? defaults.relativeModified
        foldersFirst = value(FileSettings.foldersFirstKey)?.bool ?? defaults.foldersFirst
        showHidden = value(FileSettings.showHiddenKey)?.bool ?? defaults.showHidden
        dateStyle =
            value(FileSettings.dateStyleKey)?.string.flatMap(DateStyle.init(rawValue:))
            ?? defaults.dateStyle
        use24Hour = value(FileSettings.use24HourKey)?.bool ?? defaults.use24Hour
        if let days = value(FileSettings.emptyTrashAfterKey)?.int {
            emptyTrashAfter = days > 0 ? days : nil
        }
    }

    func rowStyle(now: Date) -> FileRowStyle {
        return FileRowStyle(
            showExtensions: showExtensions, showDetails: showDetails,
            relativeModified: relativeModified, dateStyle: dateStyle, use24Hour: use24Hour,
            now: now)
    }

    /// A date for Info.
    func date(_ date: Date) -> String {
        return DateDisplay.string(
            for: date, now: Date(), relative: false, style: dateStyle, use24Hour: use24Hour)
    }
}

/// What the phone's screens need of the link.
struct FilesLinkState: Equatable, Sendable {
    /// `nil` until the session is active.
    var status: LinkStatus?
    var isReachable = false
    var epoch: String?
    var directory: URL?
    var display = FilesDisplay()
}

/// Files on the phone: live while connected, otherwise what user info brings or
/// the cache. It follows the link, keeps the cache pointed at the right place,
/// and tells the screen on top when to read again.
@MainActor @Observable
final class WatchFiles {
    /// Whether Dialect is in front on the watch, debounced: lowering the wrist
    /// ends reachability within moments and raising it brings it back, and a
    /// background wake makes it flap.
    private(set) var isConnected = false
    private(set) var link = FilesLinkState()

    @ObservationIgnored let connection: any FilesConnection
    @ObservationIgnored let cache: FilesCache

    @ObservationIgnored private let connectAfter: Duration
    @ObservationIgnored private let disconnectAfter: Duration

    /// How long a screen waits before asking again for totals still pending.
    @ObservationIgnored let pendingRetry: Duration

    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var cacheUpdate: Task<Void, Never>?
    @ObservationIgnored private weak var top: (any BrowsingModel)?

    /// The screens that have shown, which another Dialect clears.
    @ObservationIgnored private var screens: [Screen] = []

    /// The last Dialect heard from, which the link forgets while the status
    /// hides Files.
    @ObservationIgnored private var epoch: String?

    private struct Screen {
        weak var model: (any BrowsingModel)?
    }

    init(
        connection: any FilesConnection, cache: FilesCache = FilesCache(),
        preparing: Task<Void, Never>? = nil, connectAfter: Duration = .milliseconds(500),
        disconnectAfter: Duration = .seconds(3),
        pendingRetry: Duration = .seconds(1)
    ) {
        self.connection = connection
        self.cache = cache
        self.connectAfter = connectAfter
        self.disconnectAfter = disconnectAfter
        self.pendingRetry = pendingRetry
        cacheUpdate = preparing
    }

    /// Whether the status lets the phone show the watch's files at all.
    var canAsk: Bool { link.status?.showsSettings == true }

    /// The screen on top, as it appears.
    func showing(_ model: any BrowsingModel) {
        top = model
        screens.removeAll { $0.model == nil || $0.model === model }
        screens.append(Screen(model: model))
    }

    /// Reads `model`. An answer heard while not connected reads as the cache
    /// once the disconnect wait passes without a connection.
    func refresh(_ model: any BrowsingModel) async {
        await model.refresh()
        guard !isConnected else { return }
        try? await Task.sleep(for: disconnectAfter)
        if !isConnected { model.connectionEnded() }
    }

    /// Takes the link's latest state.
    func follow(_ state: FilesLinkState) {
        let old = link
        link = state

        if state.directory != old.directory || state.epoch != old.epoch {
            cacheUpdate = Task { [cache, previous = cacheUpdate] in
                await previous?.value
                await cache.use(directory: state.directory)
                await cache.use(epoch: state.epoch)
            }
        }
        let anotherDialect = epoch != nil && state.epoch != nil && state.epoch != epoch
        if let new = state.epoch { epoch = new }
        // Its files aren't the ones showing, here or further back.
        if anotherDialect {
            for screen in screens.compactMap(\.model) {
                screen.leave()
                screen.reset()
            }
        }
        if state.isReachable != old.isReachable { reachabilityChanged(to: state.isReachable) }

        // Another Dialect, the session became active, or the status began or stopped hiding Files.
        if anotherDialect || old.status == nil && state.status != nil
            || old.status?.showsSettings != state.status?.showsSettings
        {
            refreshTop()
        }
    }

    /// The app is back in front, where a screen may have been left a while.
    func becameActive() {
        refreshTop()
    }

    /// Waits for the cache to have caught up with the link.
    func cacheSettled() async {
        await cacheUpdate?.value
    }

    private func reachabilityChanged(to reachable: Bool) {
        debounce?.cancel()
        // What failed may have been a blip, so it doesn't wait for the debounce.
        let askedAgain = reachable && top?.lastRequestFailed == true
        if askedAgain { refreshTop() }
        guard reachable != isConnected else { return }
        let wait = reachable ? connectAfter : disconnectAfter
        debounce = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.settle(connected: reachable, refreshing: !askedAgain)
        }
    }

    private func settle(connected: Bool, refreshing: Bool) {
        isConnected = connected
        if !connected {
            top?.connectionEnded()
        } else if refreshing {
            refreshTop()
        }
    }

    private func refreshTop() {
        guard let top else { return }
        Task { await refresh(top) }
    }

    // MARK: Reading listings

    /// How reading a whole listing ended.
    enum ListingRead<Item: Sendable>: Sendable {
        case unchanged
        case read([Item], token: String, settings: FolderViewSettings?)
        case missing
        case failed(String)

        /// The watch is away: nobody answered.
        case noAnswer
        case otherFormat

        /// A newer read has taken over.
        case abandoned
    }

    /// One page, from any kind of listing reply.
    struct Page<Item: Sendable>: Sendable {
        let items: [Item]
        let token: String
        let total: Int
        var settings: FolderViewSettings?
    }

    /// How asking the watch once ended.
    enum Asked: Sendable {
        case reply(FilesReply)
        case noAnswer
        case failed(String)
    }

    func ask(_ body: FilesRequest.Body) async -> Asked {
        do {
            return .reply(try await connection.send(FilesRequest(body: body)))
        } catch FilesConnectionError.noAnswer {
            return .noAnswer
        } catch FilesConnectionError.timedOut {
            return .failed(String(localized: "Your watch didn't answer in time."))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static var unexpectedAnswer: String {
        return String(localized: "Your watch gave an unexpected answer.")
    }

    /// All the pages of a listing. If the listing changes between pages it
    /// starts over, once; a second change reads as a failure.
    ///
    /// - Parameters:
    ///   - token: the listing the phone has, which the watch may say is current.
    ///   - body: the request for a page at an offset, with a token.
    ///   - page: the page in a reply; `nil` for any other kind of reply.
    ///   - isCurrent: whether anyone still wants this read.
    ///   - partial: each page's items so far.
    func readListing<Item: Sendable>(
        token: String?, body: (Int, String?) -> FilesRequest.Body,
        page: (FilesReply) -> Page<Item>?, isCurrent: () -> Bool,
        partial: ([Item], FolderViewSettings?) -> Void
    ) async -> ListingRead<Item> {
        var collected: [Item] = []
        var currentListing: String?
        var asking = token
        var startedOver = false
        while true {
            let asked = await ask(body(collected.count, currentListing ?? asking))
            guard isCurrent() else { return .abandoned }
            let reply: FilesReply
            switch asked {
            case .noAnswer: return .noAnswer
            case .failed(let reason): return .failed(reason)
            case .reply(let answer): reply = answer
            }
            switch reply {
            case .unchanged:
                return .unchanged
            case .missing:
                return .missing
            case .failed(let reason):
                return .failed(reason)
            case .otherFormat:
                return .otherFormat
            default:
                guard let page = page(reply) else {
                    return .failed(Self.unexpectedAnswer)
                }
                if let listing = currentListing, page.token != listing {
                    guard !startedOver else {
                        return .failed(String(localized: "This changed while it was being read."))
                    }
                    startedOver = true
                    collected = []
                    asking = nil
                    currentListing = nil
                    continue
                }
                currentListing = page.token
                collected += page.items
                partial(collected, page.settings)
                if collected.count >= page.total || page.items.isEmpty {
                    return .read(collected, token: page.token, settings: page.settings)
                }
            }
        }
    }
}
