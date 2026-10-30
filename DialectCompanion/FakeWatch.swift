#if DEBUG
    import Foundation

    /// For UI tests and screenshots: `-fakeWatch` and a state stand in for the
    /// session, with a snapshot unlike the defaults. Edits wait as they are
    /// never applied.
    enum FakeWatch {
        static let argument = "fakeWatch"

        /// The facts for the launch argument's state, if it has one.
        static func facts(in defaults: UserDefaults = .standard) -> LinkFacts? {
            switch defaults.string(forKey: argument) {
            case "connected": return facts(reachable: true)
            case "away": return facts(reachable: false)
            case "noSnapshot": return facts(snapshot: ReceivedSnapshot.none)
            case "unpaired":
                return LinkFacts(
                    isPaired: false, isWatchAppInstalled: false, isReachable: false,
                    snapshot: .none)
            case "notInstalled":
                return LinkFacts(
                    isPaired: true, isWatchAppInstalled: false, isReachable: false,
                    snapshot: .none)
            case "oldFormat": return facts(snapshot: .otherFormat(newer: false))
            default: return nil
            }
        }

        /// Where the fake watch's cache goes, emptied each launch.
        static let cacheDirectory = FileManager.default.temporaryDirectory
            .appending(path: "FakeWatchFiles", directoryHint: .isDirectory)

        /// Files against the fake watch's tree. Away, nothing answers, and the
        /// cache holds Recents, the root, `notes` and the bin, seen an hour
        /// ago.
        @MainActor
        static func files(in defaults: UserDefaults = .standard) -> WatchFiles {
            try? FileManager.default.removeItem(at: cacheDirectory)
            let tree = FakeTree()
            guard defaults.string(forKey: argument) == "away" else {
                return WatchFiles(connection: FakeFilesConnection(handler: tree.answer))
            }
            let cache = FilesCache()
            let seeding = Task {
                await cache.use(directory: cacheDirectory)
                await cache.use(epoch: snapshot.epoch)
                await tree.seed(cache, epoch: snapshot.epoch, seen: Date() - 3600)
            }
            return WatchFiles(
                connection: FakeFilesConnection { _ in throw FilesConnectionError.noAnswer },
                cache: cache, preparing: seeding)
        }

        private static func facts(
            reachable: Bool = true, snapshot: ReceivedSnapshot = .readable(snapshot)
        ) -> LinkFacts {
            return LinkFacts(
                isPaired: true, isWatchAppInstalled: true, isReachable: reachable,
                snapshot: snapshot)
        }

        static let snapshot = SettingsSnapshot(
            epoch: "FAKE", settings: values.mapValues { .init(value: $0, version: 1) },
            undoSteps: 30, watchName: "Apple Watch Ultra")

        private static let values: [String: SettingValue] = [
            // The Purple swatch.
            AccentSetting.key: .string(RGBColor(sRGBRed: 0xBF, green: 0x5A, blue: 0xF2).displayP3),
            FileSettings.dateStyleKey: .string(DateStyle.iso.rawValue),
            FileSettings.use24HourKey: .bool(true),
            FileSettings.showExtensionsKey: .bool(false),
            FileSettings.showDetailsKey: .bool(true),
            FileSettings.relativeModifiedKey: .bool(false),
            FileSettings.foldersFirstKey: .bool(false),
            FileSettings.showHiddenKey: .bool(true),
            FileSettings.confirmExtensionChangesKey: .bool(false),
            FileSettings.textExtensionsKey: .strings(["fnl", "lisp", "rkt"]),
            FileSettings.emptyTrashAfterKey: .int(7),
            FileSettings.undoHistoryKey: .int(50),
            RecentsSettings.showLastKey: .int(10),
        ]
    }

    /// The fake watch's files.
    struct FakeTree: Sendable {
        private static let now = Date()

        private static func file(_ name: String, kind: FileKind, size: Int64) -> ListedItem {
            return ListedItem(
                name: name, kind: kind, size: size, created: now - 90000, modified: now - 7200,
                isReadOnly: false)
        }

        private static func folder(_ name: String, kind: FileKind = .folder) -> ListedItem {
            return ListedItem(
                name: name, kind: kind, size: nil, created: now - 90000, modified: now - 3600,
                isReadOnly: false)
        }

        let folders: [FilePath: [ListedItem]] = [
            .root: [
                folder("notes"), folder("scripts"), folder("demo.dial", kind: .session),
                file("readme.md", kind: .text, size: 1400),
                file(".profile", kind: .otherText, size: 80),
            ],
            FilePath(components: ["notes"]): [
                folder("archive"), file("ideas.md", kind: .text, size: 800),
                file(
                    "a rather long name for a note, which won't fit on one line of a row.md",
                    kind: .text, size: 64000),
                file("todo.txt", kind: .text, size: 120),
            ],
            FilePath(components: ["notes", "archive"]): [],
            FilePath(components: ["scripts"]): [file("prelude.scm", kind: .scheme, size: 2600)],
        ]

        let bin: [ListedBinItem] = [
            ListedBinItem(
                id: UUID(), name: "old notes.md", original: FilePath(components: ["old notes.md"]),
                deleted: now - 3600, kind: .text),
            ListedBinItem(
                id: UUID(), name: "drafts", original: FilePath(components: ["notes", "drafts"]),
                deleted: now - 2 * 86400, kind: .folder),
        ]

        private func item(_ path: FilePath) -> FileItem? {
            guard let name = path.name, let parent = path.parent else {
                return FileItem(
                    path: .root, kind: .folder, isDirectory: true, size: nil,
                    created: Self.now - 90000, modified: Self.now - 3600, isReadOnly: false)
            }
            return folders[parent]?.first { $0.name == name }?.item(in: parent)
        }

        private var pinned: [FileItem] { [FilePath(components: ["readme.md"])].compactMap(item) }

        private var recent: [FileItem] {
            return [
                FilePath(components: ["notes", "todo.txt"]), FilePath(components: ["demo.dial"]),
            ]
            .compactMap(item)
        }

        private static func token(of folder: FilePath) -> String {
            return "fake" + folder.display
        }

        @Sendable
        func answer(_ body: FilesRequest.Body) async throws -> FilesReply {
            switch body {
            case .list(let path, let offset, let token):
                guard let items = folders[path] else { return .missing }
                let current = Self.token(of: path)
                if offset == 0, token == current { return .unchanged }
                return .listing(
                    ListingPage(
                        items: Array(items[offset...]), settings: FolderViewSettings(),
                        token: current, total: items.count, offset: offset))
            case .sizes(let paths):
                return .sizes(
                    Dictionary(uniqueKeysWithValues: paths.map { ($0, Int64(4096)) }), pending: [])
            case .info(let path):
                guard let item = item(path) else { return .missing }
                return .info(
                    ItemInfo(
                        item: item, total: item.isDirectory ? 4096 : item.size,
                        count: folders[path]?.count,
                        extended: ExtendedInfo(
                            permissions: "rw-r--r--", access: ["Owner: Read, Write"],
                            owner: "mobile", group: "mobile", attributes: [])))
            case .recents:
                return .recents(pinned: pinned, recent: recent)
            case .bin(let offset, let token):
                if offset == 0, token == "fake bin" { return .unchanged }
                return .bin(
                    BinPage(
                        items: Array(bin[offset...]), token: "fake bin", total: bin.count,
                        offset: offset))
            }
        }

        /// What the phone would have kept from an earlier visit: not `scripts`.
        func seed(_ cache: FilesCache, epoch: String?, seen: Date) async {
            for path in [FilePath.root, FilePath(components: ["notes"])] {
                await cache.store(
                    CachedFolder(
                        items: folders[path] ?? [], settings: FolderViewSettings(),
                        token: Self.token(of: path), seen: seen), at: path, epoch: epoch)
            }
            await cache.store(
                CachedRecents(pinned: pinned, recent: recent, seen: seen), epoch: epoch)
            await cache.store(CachedBin(items: bin, token: "fake bin", seen: seen), epoch: epoch)
        }
    }
#endif
