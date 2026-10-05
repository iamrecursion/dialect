import Foundation

/// The kind of item being made or renamed.
enum NewItemKind: String, Hashable, Sendable, CaseIterable {
    case session, folder, file
}

/// What a name screen is naming.
enum NameTarget: Hashable, Sendable {
    case newFolder
    case newSession

    /// A new file with this extension, without the dot; empty for None.
    case newFile(extension: String)

    /// An existing item: its current full name, and its shape.
    case rename(String, NewItemKind)

    var kind: NewItemKind {
        switch self {
        case .newFolder: return .folder
        case .newSession: return .session
        case .newFile: return .file
        case .rename(_, let kind): return kind
        }
    }

    /// The current name when renaming; `nil` for a new item.
    var current: String? {
        guard case .rename(let name, _) = self else { return nil }
        return name
    }
}

/// Why a name is refused.
enum NameProblem: Equatable, Sendable {
    case empty
    case slash

    /// `.` and `..`, which name a folder and its parent.
    case reserved

    /// Over APFS's 255 bytes of UTF-8.
    case tooLong

    /// Something in the folder already has this name, as APFS compares names.
    case taken(String)

    /// A folder named like a session would quietly become one.
    case folderEndsInDial

    var reason: String {
        switch self {
        case .empty: return String(localized: "A name can't be empty.")
        case .slash: return String(localized: "A name can't contain “/”.")
        case .reserved: return String(localized: "This name is reserved.")
        case .tooLong: return String(localized: "This name is too long.")
        case .taken(let name): return String(localized: "An item named \(name) already exists.")
        case .folderEndsInDial:
            return String(localized: "A folder's name can't end in .dial, which marks a session.")
        }
    }
}

enum NameQuestion: Equatable, Sendable {
    /// The name starts with a dot, which hides the item.
    case hidden

    /// A file's extension changes; an empty side means there is none, so the
    /// change adds or removes one.
    case changeExtension(from: String, to: String)

    var title: String {
        switch self {
        case .hidden:
            return String(localized: "This item will be hidden.")
        case .changeExtension(let from, let to) where from.isEmpty:
            return String(localized: "Add .\(to)?")
        case .changeExtension(let from, let to) where to.isEmpty:
            return String(localized: "Remove .\(from)?")
        case .changeExtension(let from, let to):
            return String(localized: "Change .\(from) to .\(to)?")
        }
    }

    /// Several questions asked together, in order: "This item will be hidden.
    /// Remove .csv?"
    static func title(of questions: [NameQuestion]) -> String {
        return questions.map(\.title).joined(separator: " ")
    }

    /// The button that answers yes to them all: the last question's, which is
    /// more specific than the hidden question's Continue.
    static func confirmTitle(of questions: [NameQuestion]) -> String {
        return questions.last?.confirmTitle ?? String(localized: "Continue")
    }

    /// The button that answers yes.
    var confirmTitle: String {
        switch self {
        case .hidden:
            return String(localized: "Continue")
        case .changeExtension(let from, let to) where to.isEmpty:
            return String(localized: "Remove .\(from)")
        case .changeExtension(_, let to):
            return String(localized: "Use .\(to)")
        }
    }
}

/// Name checks, as pure functions: callers read the folder and pass in its
/// names.
enum NameRules {
    /// APFS's limit on a name, in bytes of UTF-8.
    static let maximumLength = 255

    /// Whether two names name the same item, as the Finder compares them:
    /// ignoring case and Unicode normalization.
    static func sameName(_ a: String, _ b: String) -> Bool {
        return a.compare(b, options: .caseInsensitive) == .orderedSame
    }

    /// Why `full` can't be used, or `nil` if it can.
    ///
    /// - Parameters:
    ///   - typed: what was typed, which must not be empty even when the full
    ///     name adds an extension to it.
    ///   - full: the name the item would have (see `fullName`).
    ///   - taken: every name in the folder, hidden ones included.
    ///   - current: the item's name when renaming, which doesn't count as
    ///     taken.
    static func problem(
        typed: String, full: String, kind: NewItemKind, taken: [String], current: String? = nil
    ) -> NameProblem? {
        if typed.isEmpty { return .empty }
        if full.contains("/") { return .slash }
        if full == "." || full == ".." { return .reserved }
        if full.utf8.count > maximumLength { return .tooLong }
        if kind == .folder && FileItem.splitName(full).ext.lowercased() == "dial" {
            return .folderEndsInDial
        }
        let others = taken.filter { name in current.map { !sameName(name, $0) } ?? true }
        if others.contains(where: { sameName($0, full) }) { return .taken(full) }
        return nil
    }

    /// The item's full name from what was typed. A session's `.dial` is added;
    /// a new file gets its chosen extension; and renaming a file with
    /// extensions hidden keeps the existing extension.
    static func fullName(typed: String, for target: NameTarget, showExtensions: Bool) -> String {
        switch target {
        case .newFolder, .rename(_, .folder):
            return typed
        case .newSession, .rename(_, .session):
            return FileItem.splitName(typed).ext.lowercased() == "dial" ? typed : typed + ".dial"
        case .newFile(let ext):
            return ext.isEmpty ? typed : "\(typed).\(ext)"
        case .rename(let current, .file):
            let ext = FileItem.splitName(current).ext
            return showExtensions || ext.isEmpty ? typed : "\(typed).\(ext)"
        }
    }

    /// What the name field starts with when renaming: the part that can be
    /// edited.
    static func editableName(of name: String, kind: NewItemKind, showExtensions: Bool) -> String {
        switch kind {
        case .folder: return name
        case .session: return FileItem.splitName(name).base
        case .file: return showExtensions ? name : FileItem.splitName(name).base
        }
    }

    /// What to ask before `new` is used, the leading dot first.
    static func questions(
        old: String?, new: String, kind: NewItemKind, confirmExtensionChanges: Bool
    ) -> [NameQuestion] {
        guard new != old else { return [] }
        var questions: [NameQuestion] = []
        if new.hasPrefix(".") && !(old?.hasPrefix(".") ?? false) {
            questions.append(.hidden)
        }
        if let old, kind == .file, confirmExtensionChanges {
            let from = FileItem.splitName(old).ext
            let to = FileItem.splitName(new).ext
            if from.lowercased() != to.lowercased() {
                questions.append(.changeExtension(from: from, to: to))
            }
        }
        return questions
    }

    // MARK: Extensions for new files

    /// Add › File's built-in extensions, without dots.
    static let builtInExtensions = [
        "scm", "sld", "md", "txt", "toml", "yaml", "json", "xml", "csv",
    ]

    /// Every extension Add › File lists: the built-in ones, the user's text
    /// extensions, then None (empty).
    static func listedExtensions(textExtensions: [String]) -> [String] {
        var listed = builtInExtensions
        for typed in textExtensions {
            let ext = FileSettings.normalizedExtension(typed)
            guard !ext.isEmpty, !listed.contains(ext) else { continue }
            listed.append(ext)
        }
        return listed + [""]
    }

    /// The listed extensions ranked by recency: those in `recent` first, most
    /// recent at the top, then the rest. A typed extension that isn't listed
    /// comes first only while it's the most recent.
    static func rankedExtensions(recent: [String], textExtensions: [String]) -> [String] {
        let listed = listedExtensions(textExtensions: textExtensions)
        var ranked: [String] = []
        for (index, ext) in recent.enumerated()
        where !ranked.contains(ext) && (listed.contains(ext) || index == 0) {
            ranked.append(ext)
        }
        return ranked + listed.filter { !ranked.contains($0) }
    }

    /// `recent` once `used` has made a file: `used` moves to the front, and
    /// anything no longer listed drops out.
    static func recording(_ used: String, in recent: [String], listed: [String]) -> [String] {
        return [used] + recent.filter { $0 != used && listed.contains($0) }
    }
}
