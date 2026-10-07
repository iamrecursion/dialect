import SwiftUI
import WatchKit

/// The clipboard's icons.
enum ClipboardSymbol {
    static let copy = "document.on.clipboard"
    static let paste = "document.on.document"
    static let move = "square.and.arrow.down.on.square"
    static let clear = "clear"
}

extension FileOperations {
    /// Puts `paths` on the clipboard with a tap on the wrist, so a Copy is felt
    /// as well as seen in the Clipboard button's count.
    @MainActor
    static func copyWithTap(_ paths: [FilePath]) async throws {
        try await FilesRoot.operations.copy(paths)
        WKInterfaceDevice.current().play(.click)
    }
}

/// A Paste or Move a screen has asked for.
struct TransferRequest: Equatable {
    let kind: Transfer.Kind
    let folder: FilePath
}

/// The clashes a Paste or Move has to ask about, one at a time, and the answers
/// so far.
struct ClashQueue {
    let clashes: [Clash]
    private(set) var choices: [FilePath: ClashChoice] = [:]
    private var index = 0

    init(_ clashes: [Clash]) {
        self.clashes = clashes
    }

    /// The clash to ask about; `nil` once all are answered.
    var current: Clash? { index < clashes.count ? clashes[index] : nil }

    /// How many are left to answer, the current one included.
    var remaining: Int { clashes.count - index }

    /// Answers the current clash, or it and all the rest.
    mutating func answer(_ choice: ClashChoice, toAll: Bool) {
        let end = toAll ? clashes.count : min(index + 1, clashes.count)
        for clash in clashes[index..<end] { choices[clash.source] = choice }
        index = end
    }
}

extension View {
    /// Runs the Paste or Move in `request`: asks about each clash, then acts,
    /// then calls `done`. A refusal or failure shows an alert. `request` is set
    /// to `nil` when it's over, so a screen can ignore taps meanwhile.
    func clipboardTransfer(
        _ request: Binding<TransferRequest?>, done: @escaping () -> Void
    ) -> some View {
        return modifier(ClipboardTransferModifier(request: request, done: done))
    }
}

private struct ClipboardTransferModifier: ViewModifier {
    @Binding var request: TransferRequest?
    let done: () -> Void

    @State private var queue = ClashQueue([])
    @State private var asking = false
    @State private var applyToAll = false
    /// Set once the last clash is answered, so the sheet's dismissal runs the
    /// operation; without it, the dismissal was the ✕.
    @State private var answered = false
    @State private var failure: OperationFailure?
    /// Set when the alert is for a Paste or Move that stopped part way, after
    /// which the screen goes back as it does when one finishes.
    @State private var stoppedPartWay = false

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, request in
                if let request { start(request) }
            }
            // Not `$asking`: in a view modifier on watchOS 27, the sheet never presents from it.
            .sheet(
                isPresented: Binding(get: { asking }, set: { asking = $0 }), onDismiss: dismissed
            ) {
                if let clash = queue.current, let request {
                    ClashScreen(
                        clash: clash, folder: request.folder, remaining: queue.remaining,
                        applyToAll: $applyToAll, choose: choose)
                }
            }
            .operationFailureAlert($failure) {
                if stoppedPartWay {
                    stoppedPartWay = false
                    done()
                }
            }
    }

    private func start(_ request: TransferRequest) {
        Task {
            do {
                queue = ClashQueue(
                    try await FilesRoot.operations.clashes(request.kind, into: request.folder))
            } catch {
                fail(request.kind, error)
                return
            }
            applyToAll = false
            answered = false
            if queue.current == nil {
                await run(request)
            } else {
                asking = true
            }
        }
    }

    private func choose(_ choice: ClashChoice) {
        queue.answer(choice, toAll: applyToAll)
        guard queue.current == nil else { return }
        answered = true
        asking = false
    }

    /// Runs once the sheet has gone, so an alert can show; the ✕ stops the
    /// whole Paste or Move.
    private func dismissed() {
        guard answered, let request else {
            request = nil
            return
        }
        answered = false
        Task { await run(request) }
    }

    private func run(_ request: TransferRequest) async {
        let operations = FilesRoot.operations
        do {
            switch request.kind {
            case .paste:
                _ = try await operations.paste(into: request.folder, choices: queue.choices)
            case .move: _ = try await operations.move(into: request.folder, choices: queue.choices)
            }
            self.request = nil
            done()
        } catch let partial as PartialFailure<Transfer> {
            let placed = partial.done.filter { $0.placed != nil }.count
            guard placed > 0 else {
                fail(request.kind, partial.underlying)
                return
            }
            stoppedPartWay = true
            failure = OperationFailure(
                request.kind.failureTitle,
                reason: request.kind.stoppedNote(
                    placed: placed, reason: partial.underlying.localizedDescription))
            self.request = nil
        } catch {
            fail(request.kind, error)
        }
    }

    private func fail(_ kind: Transfer.Kind, _ error: any Error) {
        failure = OperationFailure(kind.failureTitle, error)
        request = nil
    }
}

extension Transfer.Kind {
    var failureTitle: LocalizedStringResource {
        return self == .paste ? "Couldn't Paste" : "Couldn't Move"
    }

    /// What a Paste or Move says when it stops part way: how many items it
    /// placed, and why it stopped.
    func stoppedNote(placed: Int, reason: String) -> String {
        let note =
            switch (self, placed == 1) {
            case (.paste, true): String(localized: "1 item was pasted before Paste stopped.")
            case (.paste, false):
                String(localized: "\(placed) items were pasted before Paste stopped.")
            case (.move, true): String(localized: "1 item was moved before Move stopped.")
            case (.move, false):
                String(localized: "\(placed) items were moved before Move stopped.")
            }
        return "\(note) \(reason)"
    }
}

/// What to do with an item whose name is taken where it's going.
struct ClashScreen: View {
    let clash: Clash
    let folder: FilePath
    let remaining: Int
    @Binding var applyToAll: Bool
    let choose: (ClashChoice) -> Void

    var body: some View {
        List {
            Text(Self.title(existing: clash.existing, folder: folder))
                .listRowBackground(Color.clear)
            // Set before choosing, as it applies to the choice.
            if remaining > 1 {
                Toggle("Apply to All", isOn: $applyToAll)
            }
            Button("Keep Both") { choose(.keepBoth) }
            if clash.canReplace {
                Button("Replace", role: .destructive) { choose(.replace) }
            }
            Button("Skip") { choose(.skip) }
        }
    }

    nonisolated static func title(existing: String, folder: FilePath) -> String {
        let place = folder.name ?? String(localized: "Files")
        return String(localized: "An item named \(existing) already exists in \(place).")
    }
}
