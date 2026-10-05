import Foundation
import Testing

@testable import Dialect

/// Name checks: what's refused, what's asked first, and how a typed name
/// becomes the item's full name.
struct NameRulesTests {
    private func problem(
        _ typed: String, _ kind: NewItemKind = .file, taken: [String] = [],
        current: String? = nil
    ) -> NameProblem? {
        return NameRules.problem(
            typed: typed, full: typed, kind: kind, taken: taken, current: current)
    }

    // MARK: Refusals

    @Test func refusesAnEmptyName() {
        #expect(problem("") == .empty)
        // A file with a kept extension still needs a base name.
        #expect(NameRules.problem(typed: "", full: ".scm", kind: .file, taken: []) == .empty)
    }

    @Test func refusesASlash() {
        #expect(problem("a/b") == .slash)
        #expect(problem("/") == .slash)
    }

    @Test func refusesTheReservedNames() {
        #expect(problem(".") == .reserved)
        #expect(problem("..") == .reserved)
        #expect(problem("...") == nil)
    }

    @Test func allowsAColon() {
        #expect(problem("12:30 notes") == nil)
    }

    /// APFS allows 255 bytes of UTF-8 in a name, whatever the characters.
    @Test func refusesANameTooLong() {
        let fits = String(repeating: "é", count: 127) + "a"  // 2 × 127 + 1 = 255 bytes
        let over = String(repeating: "é", count: 128)  // 256 bytes
        #expect(fits.utf8.count == 255)
        #expect(problem(fits) == nil)
        #expect(problem(over) == .tooLong)
    }

    @Test func refusesATakenName() {
        #expect(problem("notes.md", taken: ["notes.md"]) == .taken("notes.md"))
        #expect(problem("NOTES.md", taken: ["notes.md"]) == .taken("NOTES.md"))
        #expect(problem("notes.md", taken: ["todo.txt"]) == nil)
    }

    /// APFS compares names in either Unicode form as the same.
    @Test func refusesATakenNameInTheOtherNormalization() {
        let composed = "Caf\u{E9}.md"
        let decomposed = "Cafe\u{301}.md"
        #expect(Array(composed.unicodeScalars) != Array(decomposed.unicodeScalars))
        #expect(problem(composed, taken: [decomposed]) == .taken(composed))
        #expect(problem(decomposed, taken: [composed]) == .taken(decomposed))
    }

    /// Hidden items take their names too, whatever Show Hidden says.
    @Test func countsHiddenNamesAsTaken() {
        #expect(problem(".config", taken: [".config"]) == .taken(".config"))
    }

    /// Renaming an item to its name in another case or form is allowed.
    @Test func allowsARenameOfOnlyTheCase() {
        #expect(problem("notes.md", taken: ["Notes.md", "todo.txt"], current: "Notes.md") == nil)
        #expect(
            problem("Cafe\u{301}.md", taken: ["Caf\u{E9}.md"], current: "Caf\u{E9}.md") == nil)
        #expect(
            problem("todo.txt", taken: ["Notes.md", "todo.txt"], current: "Notes.md")
                == .taken("todo.txt"))
    }

    /// A folder named like a session would quietly become one.
    @Test func refusesAFolderEndingInDial() {
        #expect(problem("x.dial", .folder) == .folderEndsInDial)
        #expect(problem("x.DIAL", .folder) == .folderEndsInDial)
        #expect(problem("x.dial", .file) == nil)
        #expect(problem("dial", .folder) == nil)
    }

    @Test func givesEachRefusalAReason() {
        let problems: [NameProblem] = [
            .empty, .slash, .reserved, .tooLong, .taken("notes.md"), .folderEndsInDial,
        ]
        for problem in problems {
            #expect(!problem.reason.isEmpty)
        }
        #expect(NameProblem.taken("notes.md").reason.contains("notes.md"))
    }

    // MARK: Full names

    @Test func makesNewNames() {
        #expect(NameRules.fullName(typed: "lib", for: .newFolder, showExtensions: true) == "lib")
        #expect(
            NameRules.fullName(typed: "scratch", for: .newSession, showExtensions: true)
                == "scratch.dial")
        #expect(
            NameRules.fullName(
                typed: "hello", for: .newFile(extension: "scm"), showExtensions: false)
                == "hello.scm")
        #expect(
            NameRules.fullName(
                typed: "Makefile", for: .newFile(extension: ""), showExtensions: true)
                == "Makefile")
    }

    /// Typing a session's `.dial` doesn't double it.
    @Test func doesNotDoubleASessionsExtension() {
        #expect(
            NameRules.fullName(typed: "demo.dial", for: .newSession, showExtensions: true)
                == "demo.dial")
        #expect(
            NameRules.fullName(typed: "demo.DIAL", for: .newSession, showExtensions: true)
                == "demo.DIAL")
        #expect(
            NameRules.fullName(
                typed: "demo.dial", for: .rename("old.dial", .session), showExtensions: true)
                == "demo.dial")
    }

    @Test func keepsTheExtensionWhenExtensionsAreHidden() {
        let target = NameTarget.rename("prelude.scm", .file)
        #expect(NameRules.fullName(typed: "base", for: target, showExtensions: false) == "base.scm")
        #expect(
            NameRules.fullName(typed: "base.txt", for: target, showExtensions: true) == "base.txt")
        #expect(
            NameRules.fullName(typed: "notes", for: .rename("readme", .file), showExtensions: false)
                == "notes")
    }

    @Test func renamesFoldersAndSessionsWhole() {
        #expect(
            NameRules.fullName(typed: "v2.old", for: .rename("v1", .folder), showExtensions: false)
                == "v2.old")
        #expect(
            NameRules.fullName(
                typed: "demo2", for: .rename("demo.dial", .session), showExtensions: false)
                == "demo2.dial")
    }

    @Test func startsTheFieldWithTheEditablePart() {
        #expect(
            NameRules.editableName(of: "prelude.scm", kind: .file, showExtensions: true)
                == "prelude.scm")
        #expect(
            NameRules.editableName(of: "prelude.scm", kind: .file, showExtensions: false)
                == "prelude")
        #expect(
            NameRules.editableName(of: "v1.old", kind: .folder, showExtensions: false) == "v1.old")
        #expect(
            NameRules.editableName(of: "demo.dial", kind: .session, showExtensions: true) == "demo")
    }

    // MARK: Questions

    private func questions(
        _ old: String?, _ new: String, _ kind: NewItemKind = .file, confirm: Bool = true
    ) -> [NameQuestion] {
        return NameRules.questions(old: old, new: new, kind: kind, confirmExtensionChanges: confirm)
    }

    @Test func asksBeforeHiding() {
        #expect(questions(nil, ".secret", .folder) == [.hidden])
        #expect(questions("todo.txt", ".todo.txt") == [.hidden])
        // Already hidden: nothing new to say.
        #expect(questions(".config", ".config2") == [])
    }

    @Test func asksBeforeChangingAnExtension() {
        #expect(questions("todo.txt", "todo.md") == [.changeExtension(from: "txt", to: "md")])
        #expect(questions("readme", "readme.md") == [.changeExtension(from: "", to: "md")])
        #expect(questions("notes.md", "notes") == [.changeExtension(from: "md", to: "")])
        // Only the case of the extension changes: not a change.
        #expect(questions("photo.JPG", "photo.jpg") == [])
    }

    @Test func asksAboutHidingFirst() {
        #expect(
            questions("todo.txt", ".todo.md") == [.hidden, .changeExtension(from: "txt", to: "md")])
    }

    @Test func dropsOnlyTheExtensionQuestionWhenNotConfirming() {
        #expect(questions("todo.txt", "todo.md", confirm: false) == [])
        #expect(questions("todo.txt", ".todo.md", confirm: false) == [.hidden])
    }

    @Test func neverAsksAboutFoldersOrSessionsExtensions() {
        #expect(questions("v1", "v1.old", .folder) == [])
        #expect(questions("demo.dial", "demo2.dial", .session) == [])
    }

    @Test func asksNothingForANewFilesExtension() {
        #expect(questions(nil, "hello.scm") == [])
    }

    @Test func asksNothingForAnUnchangedName() {
        #expect(questions("todo.txt", "todo.txt") == [])
        #expect(questions(".config", ".config") == [])
    }

    @Test func wordsTheQuestions() {
        #expect(
            NameQuestion.changeExtension(from: "scm", to: "txt").title == "Change .scm to .txt?")
        #expect(NameQuestion.changeExtension(from: "", to: "txt").title == "Add .txt?")
        #expect(NameQuestion.changeExtension(from: "scm", to: "").title == "Remove .scm?")
        #expect(NameQuestion.hidden.title == "This item will be hidden.")
        #expect(NameQuestion.hidden.confirmTitle == "Continue")
        #expect(NameQuestion.changeExtension(from: "scm", to: "txt").confirmTitle == "Use .txt")
        #expect(NameQuestion.changeExtension(from: "", to: "txt").confirmTitle == "Use .txt")
        #expect(NameQuestion.changeExtension(from: "scm", to: "").confirmTitle == "Remove .scm")
        let both: [NameQuestion] = [.hidden, .changeExtension(from: "csv", to: "")]
        #expect(NameQuestion.title(of: both) == "This item will be hidden. Remove .csv?")
        #expect(NameQuestion.confirmTitle(of: both) == "Remove .csv")
        #expect(NameQuestion.confirmTitle(of: [.hidden]) == "Continue")
    }

    // MARK: Extensions, ranked by recency

    private let builtIn = ["scm", "sld", "md", "txt", "toml", "yaml", "json", "xml", "csv"]

    @Test func ranksTheSpecsOrderOnFirstLaunch() {
        #expect(NameRules.rankedExtensions(recent: [], textExtensions: []) == builtIn + [""])
    }

    @Test func addsTheUsersTextExtensionsBeforeNone() {
        #expect(
            NameRules.rankedExtensions(recent: [], textExtensions: ["el", ".RKT", "md", " "])
                == builtIn + ["el", "rkt", ""])
    }

    @Test func ranksRecentlyUsedFirst() {
        var recent: [String] = []
        let listed = NameRules.listedExtensions(textExtensions: [])
        recent = NameRules.recording("md", in: recent, listed: listed)
        recent = NameRules.recording("txt", in: recent, listed: listed)
        let ranked = NameRules.rankedExtensions(recent: recent, textExtensions: [])
        #expect(ranked.prefix(3) == ["txt", "md", "scm"])
        #expect(ranked.count == builtIn.count + 1)

        // None is ranked like any other.
        recent = NameRules.recording("", in: recent, listed: listed)
        #expect(NameRules.rankedExtensions(recent: recent, textExtensions: []).first == "")
    }

    /// A typed extension is offered first while it's the last used, and never
    /// joins the list.
    @Test func keepsATypedExtensionOnlyWhileItsTheLastUsed() {
        let listed = NameRules.listedExtensions(textExtensions: [])
        var recent = NameRules.recording("md", in: [], listed: listed)
        recent = NameRules.recording("rkt", in: recent, listed: listed)
        #expect(
            NameRules.rankedExtensions(recent: recent, textExtensions: []).prefix(2) == [
                "rkt", "md",
            ])

        recent = NameRules.recording("scm", in: recent, listed: listed)
        let ranked = NameRules.rankedExtensions(recent: recent, textExtensions: [])
        #expect(ranked.prefix(2) == ["scm", "md"])
        #expect(!ranked.contains("rkt"))
    }

    /// A text extension since removed stays the default while it's the last
    /// used, as a typed one does, then drops out.
    @Test func dropsARemovedTextExtension() {
        let withEl = NameRules.listedExtensions(textExtensions: ["el"])
        let without = NameRules.listedExtensions(textExtensions: [])
        var recent = NameRules.recording("md", in: [], listed: withEl)
        recent = NameRules.recording("el", in: recent, listed: withEl)
        #expect(
            NameRules.rankedExtensions(recent: recent, textExtensions: []).prefix(2) == [
                "el", "md",
            ])
        recent = NameRules.recording("txt", in: recent, listed: without)
        #expect(recent == ["txt", "md"])
        #expect(!NameRules.rankedExtensions(recent: recent, textExtensions: []).contains("el"))
    }
}
