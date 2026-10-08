import SwiftUI

/// One place Path can go back to.
struct PathLevel: Identifiable, Equatable {
    let title: String
    let symbol: FileSymbol

    /// What Path goes back to; `nil` for the main menu.
    let route: Route?

    /// The folder Path was opened from, which it doesn't go to.
    let isCurrent: Bool

    /// The level as the question before a jump names it.
    var destination: String {
        return route == nil ? String(localized: "the main menu") : title
    }

    var id: Route? { route }
}

/// A folder's More › Path: the folder at the top, the folders above it, Files,
/// then the main menu. Tapping a level goes straight back to it, first asking
/// when that would drop an active selection of files.
struct PathScreen: View {
    let folder: FilePath

    /// The levels, the folder's first.
    nonisolated static func levels(for folder: FilePath, showExtensions: Bool) -> [PathLevel] {
        let components = folder.components
        let folders = components.indices.reversed().map { index in
            let path = FilePath(components: Array(components[...index]))
            let kind = FileKind.classify(
                name: components[index], isDirectory: true, textExtensions: [])
            return PathLevel(
                title: FolderScreen.displayName(
                    of: components[index], showExtensions: showExtensions),
                symbol: (kind ?? .folder).symbol, route: .folder(path),
                isCurrent: path == folder)
        }
        return folders + [
            PathLevel(
                title: String(localized: "Files"), symbol: FileKind.folder.symbol,
                route: .files, isCurrent: folder == .root),
            PathLevel(
                title: String(localized: "Menu"),
                symbol: .system("list.bullet.below.rectangle"), route: nil,
                isCurrent: false),
        ]
    }

    /// Only a selection with something in it is worth asking about.
    nonisolated static func asks(selected count: Int) -> Bool {
        return count > 0
    }

    nonisolated static func question(selected count: Int, going destination: String) -> String {
        return count == 1
            ? String(localized: "Deselect 1 item and go to \(destination)?")
            : String(localized: "Deselect \(count) items and go to \(destination)?")
    }

    @Environment(Navigation.self) private var navigation
    @Environment(FileSelection.self) private var selection
    @AppStorage(FileSettings.showExtensionsKey) private var showExtensions =
        FileSettings.showExtensionsDefault

    /// The level waiting on the question.
    @State private var asking: PathLevel?

    var body: some View {
        List {
            ForEach(Self.levels(for: folder, showExtensions: showExtensions)) { level in
                PathRow(level: level) {
                    choose(level)
                }
            }
        }
        .navigationTitle("Path")
        .confirmationDialog(
            Text(
                verbatim: asking.map {
                    Self.question(selected: selectedCount, going: $0.destination)
                } ?? ""),
            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
            titleVisibility: .visible, presenting: asking
        ) { level in
            Button("Go") { go(to: level) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// What's selected in the folder, if it's in select mode.
    private var selectedCount: Int {
        return selection.isSelecting(on: Route.folderRoute(for: folder)) ? selection.items.count : 0
    }

    private func choose(_ level: PathLevel) {
        guard !level.isCurrent else { return }
        if Self.asks(selected: selectedCount) {
            asking = level
        } else {
            go(to: level)
        }
    }

    /// Leaving the folder ends select mode, as Back does.
    private func go(to level: PathLevel) {
        if let route = level.route {
            navigation.pop(to: route)
        } else {
            navigation.popToRoot()
        }
    }
}

/// A level: its icon and name, with the current folder checked and not
/// tappable.
private struct PathRow: View {
    let level: PathLevel
    let choose: () -> Void

    @Environment(\.dialectAccent) private var accent

    /// As `FileRow`'s, so names line up with folders'.
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 30

    var body: some View {
        if level.isCurrent {
            label
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: choose) { label }
        }
    }

    private var label: some View {
        return HStack(spacing: 10) {
            level.symbol.image
                .foregroundStyle(accent)
                .font(.title3)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(verbatim: level.title)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if level.isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
            }
        }
    }
}
