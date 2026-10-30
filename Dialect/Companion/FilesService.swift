import Foundation

/// Answers the phone's requests for Files. It is read-only, and hence never
/// modifies files.
struct FilesService: Sendable {
    let root: URL
    let stores: URL

    /// Documented as safe to use from any thread.
    nonisolated(unsafe) let defaults: UserDefaults

    var sizes = FolderSizes.shared
    var kinds = FileKinds.shared

    /// How long `sizes` waits for totals before answering with what it has.
    var sizesWait = Duration.seconds(2)

    /// How old a request by user info may be and still be answered: the phone
    /// stops waiting well before this.
    static let oldestRequest: TimeInterval = 10

    /// Always answers, within a message: anything that can't be read or is too
    /// large to send is a reply saying so.
    func replyData(to data: Data) async -> Data {
        let reply: FilesReply
        if let format = try? FilesCoding.decode(Header.self, from: data).format,
            format != FilesRequest.currentFormat
        {
            reply = .otherFormat(FilesRequest.currentFormat)
        } else if let request = try? FilesCoding.decode(FilesRequest.self, from: data) {
            reply = await self.reply(to: request)
        } else {
            reply = .failed(String(localized: "Dialect on your watch couldn't read the request."))
        }
        guard let encoded = try? FilesCoding.encode(reply),
            encoded.count <= FilesPaging.messageLimit
        else {
            let tooLarge = FilesReply.failed(
                String(localized: "This is too much to send from your watch."))
            return (try? FilesCoding.encode(tooLarge)) ?? Data()
        }
        return encoded
    }

    /// The answer to a request by user info; `nil` once it's too old.
    func answer(_ request: FilesUserInfo, now: Date) async -> FilesUserInfo? {
        guard let sent = request.sent, now.timeIntervalSince(sent) <= Self.oldestRequest else {
            return nil
        }
        let data = await replyData(to: request.data)
        return FilesUserInfo(id: request.id, data: data, sent: nil)
    }

    private struct Header: Decodable {
        let format: Int
    }

    func reply(to request: FilesRequest) async -> FilesReply {
        switch request.body {
        case .list(let path, let offset, let token):
            return list(path, offset: offset, token: token)
        case .sizes(let paths):
            return await totals(of: paths)
        case .info(let path):
            return await info(path)
        case .recents:
            return recents()
        case .bin(let offset, let token):
            return bin(offset: offset, token: token)
        }
    }

    private var textExtensions: Set<String> { FileSettings.textExtensions(in: defaults) }

    // MARK: Listings

    /// A page of a folder, with every item's kind settled, hidden ones included
    /// as the phone can filter them out. A folder's view settings are part of
    /// its token, so a change to them isn't `unchanged`.
    private func list(_ path: FilePath, offset: Int, token: String?) -> FilesReply {
        guard !path.isWithin(.inbox) else { return .missing }
        let items: [ListedItem]
        do {
            items = try FileListing.items(
                in: path, root: root, showHidden: true, textExtensions: textExtensions,
                checking: kinds
            )
            .map { ListedItem($0.needsCheck ? $0.checked(as: kinds.check($0, root: root)) : $0) }
            .sorted { $0.name < $1.name }
        } catch {
            return failure(error, at: path)
        }
        let settings = FolderViewSettings.read(at: path.url(in: root))
        guard let encoded = try? items.map(FilesCoding.encode),
            let settingsData = try? FilesCoding.encode(settings)
        else { return .failed(String(localized: "Your watch couldn't describe this folder.")) }

        let current = FilesPaging.token(of: encoded, and: settingsData)
        if offset == 0, token == current { return .unchanged }
        let page = FilesPaging.page(of: encoded.map(\.count), from: offset)
        return .listing(
            ListingPage(
                items: Array(items[page]), settings: settings, token: current, total: items.count,
                offset: offset))
    }

    /// A page of the bin.
    private func bin(offset: Int, token: String?) -> FilesReply {
        let entries = BinEntry.load(
            Bin(url: FilesStores.bin(in: stores)), textExtensions: textExtensions)
        let items = entries.map {
            ListedBinItem(
                id: $0.item.id, name: $0.item.name, original: $0.item.original,
                deleted: $0.item.deleted, kind: $0.kind)
        }
        guard let encoded = try? items.map(FilesCoding.encode) else {
            return .failed(String(localized: "Your watch couldn't describe the Trash."))
        }
        let current = FilesPaging.token(of: encoded)
        if offset == 0, token == current { return .unchanged }
        let page = FilesPaging.page(of: encoded.map(\.count), from: offset)
        return .bin(
            BinPage(
                items: Array(items[page]), token: current, total: items.count, offset: offset))
    }

    private func recents() -> FilesReply {
        let listing = Recents(url: FilesStores.recents(in: stores)).listing(
            root: root, textExtensions: textExtensions,
            showHidden: defaults.bool(forKey: FileSettings.showHiddenKey),
            limit: RecentsSettings.showLast(in: defaults))
        return .recents(pinned: listing.pinned, recent: listing.recent)
    }

    // MARK: Items

    /// What's known of each total within the wait. A path that's gone, or not a
    /// folder or session, is in neither list.
    private func totals(of paths: [FilePath]) async -> FilesReply {
        let wanted = paths.filter { !$0.isWithin(.inbox) }.compactMap { path in
            (try? FileListing.item(at: path, root: root, textExtensions: []))
                .flatMap { $0.isDirectory ? $0 : nil }
        }
        return await withTaskGroup(of: (FilePath, Int64?).self) { group in
            for item in wanted {
                group.addTask { [sizes, root, sizesWait] in
                    let total = await sizes.size(
                        of: item.path, root: root, modified: item.modified, within: sizesWait)
                    return (item.path, total)
                }
            }
            var known: [FilePath: Int64] = [:]
            var pending: [FilePath] = []
            for await (path, total) in group {
                if let total {
                    known[path] = total
                } else {
                    pending.append(path)
                }
            }
            return .sizes(known, pending: pending)
        }
    }

    /// An item's Info: what's known of a folder's total at once, starting the
    /// walk for `sizes` to find.
    private func info(_ path: FilePath) async -> FilesReply {
        guard !path.isWithin(.inbox) else { return .missing }
        let item: FileItem
        do {
            item = try FileListing.item(at: path, root: root, textExtensions: textExtensions)
        } catch {
            return failure(error, at: path)
        }
        let url = path.url(in: root)
        guard item.isDirectory else {
            return .info(
                ItemInfo(
                    item: item, total: item.size, count: nil, extended: FileInfo.extended(at: url)))
        }
        let total = await sizes.size(
            of: path, root: root, modified: item.modified, within: .zero)
        return .info(
            ItemInfo(
                item: item, total: total, count: FileInfo.itemCount(of: path, root: root),
                extended: FileInfo.extended(at: url)))
    }

    private func failure(_ error: any Error, at path: FilePath) -> FilesReply {
        let exists =
            (try? FileManager.default.attributesOfItem(
                atPath: path.url(in: root).path(percentEncoded: false))) != nil
        return exists ? .failed(error.localizedDescription) : .missing
    }
}
