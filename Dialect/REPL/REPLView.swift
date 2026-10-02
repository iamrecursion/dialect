import SwiftUI

/// The most basic REPL: a scrolling transcript of plain text, each entry and
/// what it gave, and a field to type the next one in. Code is shown verbatim,
/// in a monospaced font.
struct REPLView: View {
    @State private var session = REPLSession()
    /// Changes whenever the draft is cleared, to rebuild the field: a watchOS
    /// text field can keep showing text its binding no longer holds.
    @State private var fieldGeneration = 0

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(session.entries) { entry in
                    EntryRows(entry: entry)
                        .listRowBackground(Color.clear)
                        .id(entry.id)
                }
            }
            // The field stays at the bottom of the screen, whatever the transcript's scroll.
            .safeAreaInset(edge: .bottom) {
                inputField
                    .padding(.horizontal, 4)
                    .background(.black)
            }
            .onChange(of: session.draft) { old, new in
                if new.isEmpty && !old.isEmpty { fieldGeneration += 1 }
            }
            // Keep the newest entry in view, just above the field.
            .onChange(of: session.entries.last?.evaluation) {
                guard let last = session.entries.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .navigationTitle("REPL")
        // Boot Scheme while the first entry is being typed, so it does not wait for it.
        .task { await session.start() }
        .onAppear(perform: submitDebugInput)
        .onDisappear { session.close() }
    }

    /// Shaped like the Messages input field, in the list rows' gray, with a
    /// REPL's prompt as its placeholder. watchOS draws a text field's own gray
    /// box whatever its style, so the field is drawn here, over the real one:
    /// taps pass through the drawing to the field, which opens the system's
    /// text input with the draft in it. (The real field must take the tap
    /// itself: outside a list nothing passes a tap on to it, and a
    /// near-transparent field does not get one.) Black behind the capsule hides
    /// the system box's corners, which are squarer than the capsule's ends.
    private var inputField: some View {
        ZStack {
            TextField("Scheme", text: $session.draft, prompt: Text(verbatim: Self.prompt))
                .onSubmit { Task { await session.submit() } }
                .id(fieldGeneration)
            Text(verbatim: session.draft.isEmpty ? Self.prompt : session.draft)
                .font(Self.code)
                .foregroundStyle(session.draft.isEmpty ? .secondary : .primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .background(Capsule().fill(Color.listRowGray))
                .background(.black)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The REPL's prompt: the field's placeholder, and before each entry in the
    /// transcript.
    static let prompt = "❯"

    static let code = Font.system(.footnote, design: .monospaced)

    /// For UI tests, which cannot type into watchOS's text input:
    /// `-DialectREPLInput <entry>`.
    private func submitDebugInput() {
        #if DEBUG
            // Read raw: `UserDefaults` would parse "(+ 1 2)" as a property-list array.
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "-DialectREPLInput"), flag + 1 < arguments.count
            {
                session.draft = arguments[flag + 1]
                Task { await session.submit() }
            }
        #endif
    }
}

/// An entry, then what it printed, then its result or error. Plain text
/// throughout.
private struct EntryRows: View {
    let entry: REPLSession.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(REPLView.prompt) \(entry.input)")
                .foregroundStyle(.secondary)
            if let evaluation = entry.evaluation {
                if !evaluation.output.isEmpty {
                    Text(verbatim: evaluation.output)
                }
                switch evaluation.result {
                case .value(let value): Text(verbatim: value)
                case .error(let message): Text(verbatim: message).foregroundStyle(.red)
                case .none: EmptyView()
                }
            } else {
                ProgressView()
            }
        }
        .font(REPLView.code)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        REPLView()
    }
}
