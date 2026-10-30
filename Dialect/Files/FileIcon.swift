import SwiftUI

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
