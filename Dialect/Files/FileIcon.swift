import SwiftUI

/// An icon Files shows: a system symbol, or one of Dialect's symbol templates
/// in `Assets.xcassets` (made by `utils/custom-symbols`).
enum FileSymbol: Hashable, Sendable {
    case system(String)
    case custom(String)

    /// The bin's Delete Permanently: `trash` with a warning triangle.
    static let deletePermanently = FileSymbol.custom("trash.permanent")

    var name: String {
        switch self {
        case .system(let name), .custom(let name): return name
        }
    }

    var image: Image {
        switch self {
        case .system(let name): return Image(systemName: name)
        case .custom(let name): return Image(name)
        }
    }
}

extension FileKind {
    /// The kind's icon.
    var symbol: FileSymbol {
        switch self {
        case .folder: return .system("folder.fill")
        case .session: return .custom("session")
        case .scheme: return .custom("scheme")
        case .text: return .system("text.document.fill")
        case .image: return .system("photo.fill")
        case .video: return .system("video.fill")
        case .otherText: return .system("document.fill")
        case .binary: return .system("questionmark.app.fill")
        }
    }
}

/// A kind's icon, tinted with the accent.
struct FileIcon: View {
    let kind: FileKind

    @Environment(\.dialectAccent) private var accent

    var body: some View {
        kind.symbol.image
            .foregroundStyle(accent)
            .accessibilityHidden(true)
    }
}
