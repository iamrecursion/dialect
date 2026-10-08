import SwiftUI

/// Every destination in the app. Buttons push routes onto the navigation stack;
/// the Action Button will later open a session the same way.
enum Route: Hashable {
    case newREPL
    case resumeSession
    case files
    case recents
    case downloader
    case settings
    case editorSettings
    case sessionSettings
    case appearanceSettings
    case runtimeSettings
    case fileSettings
    case textExtensions
    case recentsSettings
    case downloaderSettings
    case companionSettings
    case accentColor
    case credits
    case creditsPage(NoticeSection)

    // Files. `.files` is the root folder; everything below it is named by its path.
    /// A folder, or a session entered as one.
    case folder(FilePath)

    /// A session opened, which shows a placeholder until the REPL can open it.
    case session(FilePath)
    case itemMore(FilePath)
    case folderMore(FilePath)
    case sort(FilePath)
    case group(FilePath)
    case folderInfo(FilePath)
    case extendedInfo(FilePath)

    /// A folder's Path: the folders above it, Files and the main menu.
    case path(FilePath)

    /// A folder's Add and Clipboard screens.
    case add(FilePath)
    case clipboard(FilePath)

    /// The name screen for a new session, folder or file in the folder.
    case newItem(NewItemKind, in: FilePath)
    case rename(FilePath)

    // The bin, which is the same from every folder.
    case bin
    case binMore

    /// A bin item's information.
    case binItem(UUID)

    /// The Files item or folder this screen is about; `nil` for the rest.
    var filePath: FilePath? {
        switch self {
        case .files: return .root
        case .folder(let path), .session(let path), .itemMore(let path), .folderMore(let path),
            .sort(let path), .group(let path), .folderInfo(let path), .extendedInfo(let path),
            .add(let path), .clipboard(let path), .newItem(_, let path), .rename(let path),
            .path(let path):
            return path
        default: return nil
        }
    }

    /// The route that shows a folder: Files itself for the root.
    static func folderRoute(for folder: FilePath) -> Route {
        return folder == .root ? .files : .folder(folder)
    }

    /// The title of a destination not built yet, which shows a placeholder;
    /// `nil` for real screens.
    var placeholderTitle: LocalizedStringResource? {
        switch self {
        case .resumeSession: return "Resume Session"
        case .downloader: return "Downloader"
        case .editorSettings: return "Editor"
        case .sessionSettings: return "Sessions"
        case .runtimeSettings: return "Runtime"
        case .downloaderSettings: return "Downloader"
        case .companionSettings: return "Companion"
        case .newREPL, .settings, .appearanceSettings, .fileSettings, .textExtensions,
            .recentsSettings, .accentColor, .credits, .creditsPage, .recents:
            return nil
        case .files, .folder, .session, .itemMore, .folderMore, .sort, .group, .folderInfo,
            .extendedInfo, .path, .add, .clipboard, .newItem, .rename, .bin, .binMore, .binItem:
            return nil
        }
    }

    @MainActor @ViewBuilder var destination: some View {
        switch self {
        case .newREPL: REPLView()
        case .settings: SettingsView()
        case .appearanceSettings: AppearanceView()
        case .fileSettings: FileSettingsView()
        case .textExtensions: TextExtensionsView()
        case .recentsSettings: RecentsSettingsView()
        case .accentColor: AccentColorView()
        case .credits: CreditsView()
        case .creditsPage(let page): CreditsPageView(page: page)
        case .files: FolderScreen(path: .root)
        case .recents: RecentsScreen()
        case .folder(let path): FolderScreen(path: path)
        case .session(let path): SessionPlaceholder(path: path)
        case .itemMore(let path): ItemMoreScreen(path: path)
        case .folderMore(let path): FolderMoreScreen(path: path)
        case .sort(let path): SortScreen(path: path)
        case .group(let path): GroupScreen(path: path)
        case .folderInfo(let path): FolderInfoScreen(path: path)
        case .extendedInfo(let path): ExtendedInfoScreen(path: path)
        case .path(let folder): PathScreen(folder: folder)
        case .add(let folder): AddScreen(folder: folder)
        case .clipboard(let folder): ClipboardScreen(folder: folder)
        case .newItem(let kind, let folder): NameScreen(purpose: .create(kind, in: folder))
        case .rename(let path): NameScreen(purpose: .rename(path))
        case .bin: BinScreen()
        case .binMore: BinMoreScreen()
        case .binItem(let id): BinItemScreen(id: id)
        default: Placeholder(title: placeholderTitle ?? "")
        }
    }
}

/// A row of the menu or of Settings.
struct MenuItem: Identifiable {
    /// Localizable: looked up in the user's language, where a `String` would be
    /// shown as is.
    let title: LocalizedStringResource
    let systemImage: String
    let route: Route

    /// Moves the icon up (negative) or down, in points at the default text
    /// size, where the eye finds the glyph's center somewhere other than its
    /// bounding box does.
    var opticalOffset: CGFloat = 0

    /// Grayed out: shown, but does nothing yet.
    var isDisabled = false

    /// A number shown after the icon, such as how many items the clipboard
    /// holds; `nil` shows none.
    var count: Int?

    /// What a button does on its own screen, such as Done; its `route` is that
    /// screen's. `nil` for a button that opens `route`.
    var action: MenuAction?

    /// The count, as VoiceOver reads it.
    var countDescription: String? {
        guard let count else { return nil }
        return count == 1 ? String(localized: "1 item") : String(localized: "\(count) items")
    }

    struct ID: Hashable {
        let route: Route
        let action: MenuAction?
    }

    var id: ID { ID(route: route, action: action) }
}

/// An action a button performs on the screen showing it.
enum MenuAction: Hashable {
    case select, done, copy
}

#if DEBUG
    extension Route {
        /// Routes by the names `-DialectPath` uses.
        private static let debugNames: [String: Route] = [
            "new-repl": .newREPL, "resume": .resumeSession, "files": .files,
            "downloader": .downloader, "settings": .settings, "editor": .editorSettings,
            "session-settings": .sessionSettings, "appearance": .appearanceSettings,
            "runtime": .runtimeSettings, "file-settings": .fileSettings,
            "text-extensions": .textExtensions, "recents": .recents,
            "recents-settings": .recentsSettings,
            "downloader-settings": .downloaderSettings, "companion": .companionSettings,
            "accent-color": .accentColor, "credits": .credits, "trash": .bin,
        ]

        /// The navigation path a debug launch argument names, so screenshots
        /// can open any screen: `-DialectPath "settings/credits/License
        /// texts/CBORCoding"`. Segments name routes (see `debugNames`) until
        /// `credits`, then Credits pages by title.
        ///
        /// `folder:` takes the rest of the path as a folder below Files' root,
        /// as in `files/folder:scripts/lib`, with a route for each level;
        /// `more:` takes the rest as an item, and ends on its More screen, as
        /// in `more:notes/todo.txt`; `path:` takes it as a folder, and ends on
        /// its Path screen. `add` is Add for the folder the path has reached,
        /// `clipboard` its Clipboard, and `new-session`, `new-folder` and
        /// `new-file` its name screens, so they come before any `folder:`. The
        /// path stops at the first segment that doesn't name anything.
        static func debugPath(_ spec: String, creditsPages: [NoticeSection]?) -> [Route] {
            var path: [Route] = []

            // Set once the path reaches Credits: the pages the next segment can name.
            var pages: [NoticeSection]?

            let segments = spec.split(separator: "/").map(String.init)
            for (index, segment) in segments.enumerated() {
                for prefix in ["folder:", "more:", "path:"] where segment.hasPrefix(prefix) {
                    if path.last != .files { path.append(.files) }
                    var names =
                        ([String(segment.dropFirst(prefix.count))] + segments[(index + 1)...])
                        .filter { !$0.isEmpty }
                    // `more:` ends on the item's More screen, over the folders it's in.
                    let item = prefix == "more:" ? names.popLast() : nil
                    var folder = FilePath.root
                    for name in names {
                        folder = folder.appending(name)
                        path.append(.folder(folder))
                    }
                    if let item { path.append(.itemMore(folder.appending(item))) }
                    if prefix == "path:" { path.append(.path(folder)) }
                    return path
                }
                if segment == "add" && pages == nil {
                    path.append(.add(path.last?.filePath ?? .root))
                    continue
                }
                if segment == "clipboard" && pages == nil {
                    path.append(.clipboard(path.last?.filePath ?? .root))
                    continue
                }
                if segment.hasPrefix("new-"), pages == nil,
                    let kind = NewItemKind(rawValue: String(segment.dropFirst("new-".count)))
                {
                    path.append(.newItem(kind, in: path.last?.filePath ?? .root))
                    continue
                }
                if let candidates = pages {
                    guard let page = candidates.first(where: { $0.title == segment }) else { break }
                    path.append(.creditsPage(page))
                    pages = page.subsections
                } else {
                    guard let route = debugNames[segment] else { break }
                    path.append(route)
                    if route == .credits { pages = creditsPages ?? [] }
                }
            }
            return path
        }
    }
#endif
