import SwiftUI

/// What Undo or Redo would reverse: "Undo Rename", and beneath it the item and
/// its location when needed.
struct UndoLabel {
    let title: LocalizedStringResource
    let detail: String

    /// `here` is the folder the screen belongs to, which the line beneath
    /// doesn't repeat.
    init(_ step: Step, undoing: Bool, here: FilePath) {
        title = Self.action(step.kind, undoing: undoing)
        let changes = step.changes.filter { !$0.replaced }
        let paths = changes.compactMap(\.path)
        let what =
            paths.count == 1
            ? paths[0].name ?? "" : String(localized: "\(paths.count) items")

        // A Move's where is its destination, which Redo's changes come from.
        let folders = Set(
            changes.compactMap { change in
                if step.kind == .move && !undoing, case .files(let path)? = change.from {
                    return path.parent ?? .root
                }
                return change.path.map { $0.parent ?? .root }
            })
        if folders.count == 1, let folder = folders.first, folder != here {
            detail = String(localized: "\(what) in \(folder.messageName)")
        } else {
            detail = what
        }
    }

    private static func action(_ kind: Step.Kind, undoing: Bool) -> LocalizedStringResource {
        switch (kind, undoing) {
        case (.rename, true): return "Undo Rename"
        case (.rename, false): return "Redo Rename"
        case (.move, true): return "Undo Move"
        case (.move, false): return "Redo Move"
        case (.paste, true): return "Undo Paste"
        case (.paste, false): return "Redo Paste"
        case (.newFolder, true): return "Undo New Folder"
        case (.newFolder, false): return "Redo New Folder"
        case (.newSession, true): return "Undo New Session"
        case (.newSession, false): return "Redo New Session"
        case (.newFile, true): return "Undo New File"
        case (.newFile, false): return "Redo New File"
        case (.delete, true): return "Undo Delete"
        case (.delete, false): return "Redo Delete"
        case (.restore, true): return "Undo Restore"
        case (.restore, false): return "Redo Restore"
        }
    }
}

/// Undo and Redo, for a folder's and an item's More screens, grayed out when
/// there's nothing to undo or redo.
///
/// Each acts and goes back one step, leaving any screen showing what it took
/// away. A step it can't take is dropped, and the alert says why; one that
/// would send to the bin something changed since asks first.
struct UndoRows: View {
    /// The folder the screen belongs to.
    let here: FilePath

    @Environment(Navigation.self) private var navigation
    @State private var stacks: History.Stacks
    @State private var acting = false
    @State private var failure: OperationFailure?

    /// What to leave once the alert for a step that stopped part way is
    /// dismissed; `nil` when the step did nothing, and More stays.
    @State private var stoppedLeaving: [FilePath]?

    /// A step whose items changed since, waiting for the user to go ahead. Its
    /// question is kept while the alert closes.
    @State private var asking: UndoChanged?
    @State private var question = ""

    init(here: FilePath) {
        self.here = here
        // Read at once, so the rows are laid out with their labels: a label arriving later can be
        // cut short at the largest text.
        _stacks = State(initialValue: Self.read(FilesRoot.operations.history))
    }

    /// The history as last read, with its file's date: a More screen's body
    /// runs often, and the file changes only when Files acts.
    private static var cache: (url: URL, date: Date, stacks: History.Stacks)?

    private static func read(_ history: History) -> History.Stacks {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: history.url.path(percentEncoded: false))
        let date = attributes?[.modificationDate] as? Date
        if let date, let cache, cache.url == history.url, cache.date == date {
            return cache.stacks
        }
        let stacks = history.read()
        if let date { cache = (history.url, date, stacks) }
        return stacks
    }

    var body: some View {
        Section {
            row(undoing: true)
            row(undoing: false)
        }
        .disabled(acting)
        .operationFailureAlert($failure) {
            if let left = stoppedLeaving { leave(left) }
            stoppedLeaving = nil
        }
        .alert(
            Text(verbatim: question),
            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
            presenting: asking
        ) { changed in
            Button(changed.undoing ? "Undo" : "Redo", role: .destructive) {
                act(undoing: changed.undoing, confirmed: true)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(undoing: Bool) -> some View {
        let step = undoing ? stacks.undo.last : stacks.redo.last
        let label = step.map { UndoLabel($0, undoing: undoing, here: here) }
        return Button {
            act(undoing: undoing)
        } label: {
            MenuRowLabel(
                title: label?.title ?? (undoing ? "Undo" : "Redo"), detail: label?.detail,
                systemImage: undoing ? "arrow.uturn.backward" : "arrow.uturn.forward")
        }
        .disabled(step == nil)
    }

    private func load() {
        stacks = Self.read(FilesRoot.operations.history)
    }

    private func act(undoing: Bool, confirmed: Bool = false) {
        guard !acting else { return }
        acting = true
        let title: LocalizedStringResource = undoing ? "Couldn't Undo" : "Couldn't Redo"
        Task {
            defer { acting = false }
            let operations = FilesRoot.operations
            do {
                let vacated =
                    undoing
                    ? try await operations.undo(confirmed: confirmed)
                    : try await operations.redo(confirmed: confirmed)
                // Played as More closes, so it's felt with the change.
                if undoing { Haptics.undo() } else { Haptics.redo() }
                leave(vacated)
            } catch let changed as UndoChanged {
                question = changed.question
                asking = changed
            } catch let stopped as UndoStopped {
                stoppedLeaving = stopped.vacated
                failure = OperationFailure(
                    title,
                    reason: Self.stoppedNote(
                        undoing: undoing, done: stopped.done.filter { !$0.replaced }.count,
                        reason: stopped.underlying.localizedDescription))
            } catch {
                failure = OperationFailure(title, error)
                load()
            }
        }
    }

    /// Goes back one step, and leaves what's no longer there.
    private func leave(_ vacated: [FilePath]) {
        navigation.pop()
        for path in vacated { navigation.leave(path) }
    }

    /// What Undo or Redo says when it stops part way.
    nonisolated static func stoppedNote(undoing: Bool, done: Int, reason: String) -> String {
        let note =
            switch (undoing, done == 1) {
            case (true, true): String(localized: "1 item was undone before Undo stopped.")
            case (true, false): String(localized: "\(done) items were undone before Undo stopped.")
            case (false, true): String(localized: "1 item was redone before Redo stopped.")
            case (false, false):
                String(localized: "\(done) items were redone before Redo stopped.")
            }
        return "\(note) \(reason)"
    }
}
