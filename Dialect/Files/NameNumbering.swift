import Foundation

/// Free names for an item whose name is taken where it's going.
enum NameNumbering {
    /// `name` if it's free, otherwise the lowest free " 2", " 3", … before the
    /// extension (`notes 2.md`, `demo 2.dial`).
    static func nextFree(for name: String, isDirectory: Bool, taken: [String]) -> String {
        func isTaken(_ candidate: String) -> Bool {
            return taken.contains { NameRules.sameName($0, candidate) }
        }
        guard isTaken(name) else { return name }
        let (base, ext) = parts(of: name, isDirectory: isDirectory)
        let stem = unnumbered(base)
        var number = 2
        while true {
            let candidate = fitted(stem, adding: " \(number)", ext)
            if !isTaken(candidate) { return candidate }
            number += 1
        }
    }

    /// The name of a copy beside its original: `notes copy.md`, then the lowest
    /// free `notes copy 2.md`, …. A copy of a copy carries on its numbering.
    static func copyName(for name: String, isDirectory: Bool, taken: [String]) -> String {
        let word =
            " "
            + String(localized: "copy", comment: "Added to a pasted copy's name: “notes copy.md”.")
        let (base, ext) = parts(of: name, isDirectory: isDirectory)
        let stem = withoutCopy(unnumbered(base), word) ?? withoutCopy(base, word) ?? base
        var candidate = fitted(stem, adding: word, ext)
        var number = 2
        while taken.contains(where: { NameRules.sameName($0, candidate) }) {
            candidate = fitted(stem, adding: "\(word) \(number)", ext)
            number += 1
        }
        return candidate
    }

    /// `base` without a trailing `word`, compared case-insensitively; `nil`
    /// when it doesn't end in it, or is nothing else.
    private static func withoutCopy(_ base: String, _ word: String) -> String? {
        guard let range = base.range(of: word, options: [.caseInsensitive, .anchored, .backwards]),
            range.lowerBound != base.startIndex
        else { return nil }
        return String(base[..<range.lowerBound])
    }

    /// The name with the local date of its deletion before its extension, as
    /// `notes-2026-10-05.md`.
    static func dated(
        _ name: String, isDirectory: Bool, deleted: Date, timeZone: TimeZone = .current
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = calendar.dateComponents([.year, .month, .day], from: deleted)
        let date = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        let (base, ext) = parts(of: name, isDirectory: isDirectory)
        return fitted(base, adding: "-\(date)", ext)
    }

    /// A name split where a number or date goes: before the extension, except
    /// for a folder, whose name is all base.
    private static func parts(of name: String, isDirectory: Bool) -> (base: String, ext: String) {
        let split = FileItem.splitName(name)
        if isDirectory && split.ext.lowercased() != "dial" { return (name, "") }
        return split
    }

    /// `base`, `suffix` and the extension, with `base` shortened until the name
    /// fits in `NameRules.maximumLength` bytes.
    private static func fitted(_ base: String, adding suffix: String, _ ext: String) -> String {
        var base = Substring(base)
        while true {
            let name = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            if name.utf8.count <= NameRules.maximumLength || base.isEmpty { return name }
            base = base.dropLast()
        }
    }

    /// The base without a trailing " N", where N is a whole number of 2 or
    /// more.
    private static func unnumbered(_ base: String) -> String {
        guard let space = base.lastIndex(of: " ") else { return base }
        let digits = base[base.index(after: space)...]
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
            let number = Int(digits), number >= 2
        else { return base }
        return String(base[..<space])
    }
}
