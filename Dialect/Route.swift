import SwiftUI

/// Every destination in the app. Buttons push routes onto the navigation stack;
/// the Action Button will later open a session the same way (D12).
enum Route: Hashable {
    case newREPL
    case resumeSession
    case sessions
    case files
    case downloader
    case settings
    case editorSettings
    case sessionSettings
    case appearanceSettings
    case runtimeSettings
    case fileSettings
    case downloaderSettings
    case companionSettings
    case accentColor
    case credits
    case creditsPage(NoticeSection)

    /// The title of a destination not built yet, which shows a placeholder;
    /// `nil` for real screens.
    var placeholderTitle: LocalizedStringResource? {
        switch self {
        case .resumeSession: return "Resume Session"
        case .sessions: return "History"
        case .files: return "Files"
        case .downloader: return "Downloader"
        case .editorSettings: return "Editor"
        case .sessionSettings: return "Sessions"
        case .runtimeSettings: return "Runtime"
        case .fileSettings: return "Files"
        case .downloaderSettings: return "Downloader"
        case .companionSettings: return "Companion"
        case .newREPL, .settings, .appearanceSettings, .accentColor, .credits, .creditsPage:
            return nil
        }
    }

    @MainActor @ViewBuilder var destination: some View {
        switch self {
        case .newREPL: REPLView()
        case .settings: SettingsView()
        case .appearanceSettings: AppearanceView()
        case .accentColor: AccentColorView()
        case .credits: CreditsView()
        case .creditsPage(let page): CreditsPageView(page: page)
        default: Placeholder(title: placeholderTitle ?? "")
        }
    }
}

/// A row of the menu or of Settings.
struct MenuItem: Identifiable {
    /// Localizable: looked up in the wearer's language, where a `String` would
    /// be shown as is.
    let title: LocalizedStringResource
    let systemImage: String
    let route: Route
    /// Moves the icon up (negative) or down, in points at the default text
    /// size, where the eye finds the glyph's center somewhere other than its
    /// bounding box does.
    var opticalOffset: CGFloat = 0

    var id: Route { route }
}

#if DEBUG
    extension Route {
        /// Routes by the names `-DialectPath` uses.
        private static let debugNames: [String: Route] = [
            "new-repl": .newREPL, "resume": .resumeSession, "sessions": .sessions, "files": .files,
            "downloader": .downloader, "settings": .settings, "editor": .editorSettings,
            "session-settings": .sessionSettings, "appearance": .appearanceSettings,
            "runtime": .runtimeSettings, "file-settings": .fileSettings,
            "downloader-settings": .downloaderSettings, "companion": .companionSettings,
            "accent-color": .accentColor, "credits": .credits,
        ]

        /// The navigation path a debug launch argument names, so screenshots
        /// can open any screen: `-DialectPath "settings/credits/License
        /// texts/CBORCoding"`. Segments name routes (see `debugNames`) until
        /// `credits`, then Credits pages by title. The path stops at the first
        /// segment that names nothing.
        static func debugPath(_ spec: String, creditsPages: [NoticeSection]?) -> [Route] {
            var path: [Route] = []
            // Set once the path reaches Credits: the pages the next segment can name.
            var pages: [NoticeSection]?
            for segment in spec.split(separator: "/").map(String.init) {
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
