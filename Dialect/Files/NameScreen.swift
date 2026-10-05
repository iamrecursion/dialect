import SwiftUI

/// What the name screen is for.
enum NamePurpose: Hashable {
    case create(NewItemKind, in: FilePath)
    case rename(FilePath)

    /// The folder the name must be free in.
    var folder: FilePath {
        switch self {
        case .create(_, let folder): return folder
        case .rename(let path): return path.parent ?? .root
        }
    }
}

/// The name screen: a field for the name, a new file's extension, and Create
/// (or Rename).
struct NameScreen: View {
    let purpose: NamePurpose

    @Environment(Navigation.self) private var navigation
    @AppStorage(FileSettings.showExtensionsKey) private var showExtensions =
        FileSettings.showExtensionsDefault
    @AppStorage(FileSettings.confirmExtensionChangesKey) private var confirmExtensionChanges =
        FileSettings.confirmExtensionChangesDefault

    @State private var typed = ""
    @State private var problem: NameProblem?

    /// The item being renamed, once read; `nil` for a new item.
    @State private var renaming: (name: String, kind: NewItemKind)?
    @State private var missing = false

    /// A new file's extensions, most recently used first, and the choice.
    @State private var ranked: [String] = []
    @State private var extensionChoice = ExtensionChoice.listed("")
    @State private var otherExtension = ""
    @State private var extensionProblem: TextExtensionProblem?

    /// A name waiting on its questions.
    @State private var asking: Asking?

    @State private var prepared = false
    @State private var working = false
    @State private var failure: OperationFailure?

    /// A name and the questions to answer before it's used, asked together in
    /// one dialog.
    struct Asking {
        let full: String
        let target: NameTarget
        let questions: [NameQuestion]
    }

    /// A choice in Add › File's extension list: one of the ranked extensions
    /// (empty for None), or Other…, which is typed.
    enum ExtensionChoice: Hashable {
        case listed(String)
        case other
    }

    var body: some View {
        List {
            if case .rename = purpose, renaming == nil {
                if missing { MissingItem() }
            } else {
                // Finishing text input only fills the field; Create or Rename acts, so a new file's
                // extension can still be chosen.
                Section {
                    TextField("Name", text: $typed)
                    if let problem {
                        reason(problem.reason)
                    }
                }
                // A session's `.dial` can't be changed, so it isn't shown at all.
                if case .create(.file, _) = purpose {
                    extensionSection
                }
                Section {
                    Button(action: submit) {
                        Text(isRenaming ? "Rename" : "Create")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(working)
                }
            }
        }
        .navigationTitle(title)
        .onChange(of: typed) { problem = nil }
        .onChange(of: extensionChoice) { problem = nil }
        .onChange(of: otherExtension) {
            problem = nil
            extensionProblem = nil
        }
        .confirmationDialog(
            Text(verbatim: asking.map { NameQuestion.title(of: $0.questions) } ?? ""),
            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
            titleVisibility: .visible, presenting: asking
        ) { asking in
            Button(NameQuestion.confirmTitle(of: asking.questions)) { answerYes(asking) }
            Button("Cancel", role: .cancel) {}
        }
        .operationFailureAlert($failure)
        .task { await prepare() }
    }

    private var isRenaming: Bool {
        if case .rename = purpose { return true }
        return false
    }

    private var kind: NewItemKind {
        switch purpose {
        case .create(let kind, _): return kind
        case .rename: return renaming?.kind ?? .file
        }
    }

    private var title: Text {
        switch purpose {
        case .create(.session, _): return Text("New Session")
        case .create(.folder, _): return Text("New Folder")
        case .create(.file, _): return Text("New File")
        case .rename: return Text("Rename")
        }
    }

    private var extensionSection: some View {
        Section {
            Picker("Extension", selection: $extensionChoice) {
                ForEach(ranked, id: \.self) { ext in
                    Text(verbatim: Self.label(ext)).tag(ExtensionChoice.listed(ext))
                }
                Text("Other…").tag(ExtensionChoice.other)
            }
            .pickerStyle(.navigationLink)
            if extensionChoice == .other {
                TextField("Extension", text: $otherExtension)
                if let extensionProblem {
                    reason(extensionProblem.reason)
                }
            }
        }
    }

    /// An extension as the list shows it: with its dot, or None.
    nonisolated static func label(_ ext: String) -> String {
        return ext.isEmpty ? String(localized: "None") : ".\(ext)"
    }

    private func reason(_ text: String) -> some View {
        return Text(verbatim: text)
            .font(.footnote)
            .foregroundStyle(.red)
    }

    // MARK: Preparing

    /// Fills in the extension list, or reads the item being renamed.
    private func prepare() async {
        guard !prepared else { return }
        prepared = true
        switch purpose {
        case .create(.file, _):
            let typedExtensions =
                UserDefaults.standard.stringArray(forKey: FileSettings.textExtensionsKey) ?? []
            ranked = NameRules.rankedExtensions(
                recent: FileSettings.recentExtensions(), textExtensions: typedExtensions)
            extensionChoice = .listed(ranked.first ?? "")
        case .create:
            break
        case .rename(let path):
            let root = FilesRoot.url
            let item = await Task.detached {
                try? FileListing.item(at: path, root: root, textExtensions: [])
            }.value
            guard let item else {
                missing = true
                return
            }
            let kind: NewItemKind =
                switch item.kind {
                case .folder: .folder
                case .session: .session
                default: .file
                }
            renaming = (item.name, kind)
            typed = NameRules.editableName(
                of: item.name, kind: kind, showExtensions: showExtensions)
        }
        fillDebugInput()
    }

    /// For UI tests, which can't type into watchOS's text input:
    /// `-DialectNameInput <name>` fills the field. Read raw, as the REPL's is.
    private func fillDebugInput() {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "-DialectNameInput"), flag + 1 < arguments.count
            {
                typed = arguments[flag + 1]
            }
        #endif
    }

    // MARK: Submitting

    /// Checks the name against the folder as it is now, asks for what it needs
    /// from the user, then makes or renames the item.
    private func submit() {
        guard !working, let target = target() else { return }
        let full = NameRules.fullName(typed: typed, for: target, showExtensions: showExtensions)
        if full == target.current {
            leave()
            return
        }
        working = true
        Task {
            defer { working = false }
            let folderURL = purpose.folder.url(in: FilesRoot.url)
            let taken = await Task.detached {
                try? FileManager.default.contentsOfDirectory(
                    atPath: folderURL.path(percentEncoded: false))
            }.value
            guard let taken else {
                failure = OperationFailure(
                    failureTitle,
                    FileOperationError.gone(purpose.folder.name ?? String(localized: "Files")))
                return
            }
            if let refused = NameRules.problem(
                typed: typed, full: full, kind: target.kind, taken: taken,
                current: target.current)
            {
                problem = refused
                return
            }
            let asked = NameRules.questions(
                old: target.current, new: full, kind: target.kind,
                confirmExtensionChanges: confirmExtensionChanges)
            if asked.isEmpty {
                await perform(full, target)
            } else {
                asking = Asking(full: full, target: target, questions: asked)
            }
        }
    }

    /// What's being named, with a new file's extension.
    private func target() -> NameTarget? {
        switch purpose {
        case .create(.folder, _): return .newFolder
        case .create(.session, _): return .newSession
        case .create(.file, _):
            switch extensionChoice {
            case .listed(let ext): return .newFile(extension: ext)
            case .other:
                let ext = FileSettings.normalizedExtension(otherExtension)
                if ext.isEmpty {
                    extensionProblem = .empty
                } else if ext.contains("/") {
                    extensionProblem = .slash
                } else if ext.contains(".") {
                    extensionProblem = .dot
                } else {
                    return .newFile(extension: ext)
                }
                return nil
            }
        case .rename:
            guard let renaming else { return nil }
            return .rename(renaming.name, renaming.kind)
        }
    }

    private func answerYes(_ asking: Asking) {
        Task {
            working = true
            await perform(asking.full, asking.target)
            working = false
        }
    }

    private func perform(_ full: String, _ target: NameTarget) async {
        let operations = FilesRoot.operations
        do {
            switch purpose {
            case .create(let kind, let folder):
                switch kind {
                case .folder: _ = try await operations.createFolder(named: full, in: folder)
                case .session: _ = try await operations.createSession(named: full, in: folder)
                case .file: _ = try await operations.createFile(named: full, in: folder)
                }
                if case .newFile(let ext) = target {
                    FileSettings.recordExtension(ext)
                }
            case .rename(let path):
                _ = try await operations.rename(path, to: full)
            }
            leave()
        } catch FileOperationError.name(let refused) {
            problem = refused
        } catch {
            failure = OperationFailure(failureTitle, error)
        }
    }

    private var failureTitle: LocalizedStringResource {
        return isRenaming ? "Couldn't Rename" : "Couldn't Create"
    }

    /// Back to the folder, past Add or More, which this screen replaced.
    private func leave() {
        let folder = Route.folderRoute(for: purpose.folder)
        if navigation.path.contains(folder) {
            navigation.pop(to: folder)
        } else {
            navigation.pop()
        }
    }
}

/// A folder's Add: Session, Folder and File, each replacing Add with its name
/// screen, so Back from there goes to the folder.
struct AddScreen: View {
    let folder: FilePath

    static let items: [(kind: NewItemKind, title: LocalizedStringResource, symbol: FileSymbol)] = [
        (.session, "Session", .custom("session")),
        (.folder, "Folder", .system("folder")),
        (.file, "File", .system("document")),
    ]

    @Environment(Navigation.self) private var navigation

    var body: some View {
        List {
            ForEach(Self.items, id: \.kind) { item in
                Button {
                    navigation.replaceTop(with: .newItem(item.kind, in: folder))
                } label: {
                    MenuRowLabel(title: item.title, symbol: item.symbol)
                }
            }
        }
        .navigationTitle("Add")
    }
}
