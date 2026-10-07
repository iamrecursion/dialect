import Foundation
import Testing

@testable import Dialect

/// What Undo and Redo say they would do.
struct UndoLabelTests {
    private static func step(_ kind: Step.Kind, _ paths: [String], replacing: String? = nil)
        -> Step
    {
        var changes = paths.map { Step.Change(from: nil, to: .files(FilePath($0))) }
        if let replacing {
            let record = Bin.Record(
                name: "old", original: FilePath(replacing).components, deleted: Date())
            changes.insert(
                Step.Change(
                    from: .files(FilePath(replacing)), to: .bin(id: UUID(), record: record),
                    replaced: true), at: 0)
        }
        return Step(kind: kind, changes: changes)
    }

    @Test func titlesEachKind() {
        let titles: [(Step.Kind, String, String)] = [
            (.rename, "Undo Rename", "Redo Rename"),
            (.move, "Undo Move", "Redo Move"),
            (.paste, "Undo Paste", "Redo Paste"),
            (.newFolder, "Undo New Folder", "Redo New Folder"),
            (.newSession, "Undo New Session", "Redo New Session"),
            (.newFile, "Undo New File", "Redo New File"),
            (.delete, "Undo Delete", "Redo Delete"),
            (.restore, "Undo Restore", "Redo Restore"),
        ]
        for (kind, undo, redo) in titles {
            let step = Self.step(kind, ["a.txt"])
            #expect(String(localized: UndoLabel(step, undoing: true, here: .root).title) == undo)
            #expect(String(localized: UndoLabel(step, undoing: false, here: .root).title) == redo)
        }
    }

    /// The item's name, with where it is when that's elsewhere.
    @Test func namesTheItemAndWhereItIs() {
        let step = Self.step(.rename, ["notes/todo.txt"])
        #expect(UndoLabel(step, undoing: true, here: FilePath("notes")).detail == "todo.txt")
        #expect(UndoLabel(step, undoing: true, here: .root).detail == "todo.txt in /notes")
        let atRoot = Self.step(.newFolder, ["lib"])
        #expect(UndoLabel(atRoot, undoing: true, here: FilePath("notes")).detail == "lib in Files")
    }

    /// A Move's where is its destination, both ways.
    @Test func placesAMoveAtItsDestination() {
        let undo = Step(
            kind: .move,
            changes: [
                Step.Change(
                    from: .files(FilePath("notes/todo.txt")),
                    to: .files(FilePath("archive/todo.txt")))
            ])
        let redo = Step(
            kind: .move,
            changes: [
                Step.Change(
                    from: .files(FilePath("archive/todo.txt")),
                    to: .files(FilePath("notes/todo.txt")))
            ])
        #expect(UndoLabel(undo, undoing: true, here: .root).detail == "todo.txt in /archive")
        #expect(UndoLabel(redo, undoing: false, here: .root).detail == "todo.txt in /archive")
    }

    /// An item in the bin is named by where it was.
    @Test func namesAnItemInTheBinByWhereItWas() {
        let record = Bin.Record(
            name: "todo 2.txt", original: ["notes", "todo.txt"], deleted: Date())
        let step = Step(
            kind: .delete,
            changes: [
                Step.Change(
                    from: .files(FilePath("notes/todo.txt")), to: .bin(id: UUID(), record: record))
            ])
        #expect(UndoLabel(step, undoing: true, here: .root).detail == "todo.txt in /notes")
    }

    /// Replace's item isn't counted.
    @Test func countsSeveralItems() {
        let step = Self.step(
            .paste, ["archive/a.txt", "archive/b.txt"], replacing: "archive/a.txt")
        #expect(UndoLabel(step, undoing: true, here: FilePath("archive")).detail == "2 items")
        #expect(UndoLabel(step, undoing: true, here: .root).detail == "2 items in /archive")
        let one = Self.step(.paste, ["archive/a.txt"], replacing: "archive/a.txt")
        #expect(UndoLabel(one, undoing: true, here: .root).detail == "a.txt in /archive")
        let scattered = Self.step(.restore, ["a/x.txt", "b/y.txt"])
        #expect(UndoLabel(scattered, undoing: true, here: .root).detail == "2 items")
    }

    // MARK: Alerts

    @Test func saysWhyAStepCantBeTaken() {
        let notes = FilePath("notes")
        let messages: [(UndoProblem.Reason, String)] = [
            (
                .gone("todo.txt", in: notes),
                "This can't be undone, as todo.txt is no longer in /notes."
            ),
            (
                .gone("todo.txt", in: .root),
                "This can't be undone, as todo.txt is no longer in Files."
            ),
            (
                .taken("todo.txt", in: notes),
                "This can't be undone, as something in /notes now has the name todo.txt."
            ),
            (.folderGone(notes), "This can't be undone, as /notes is no longer there."),
            (.notAFolder(notes), "This can't be undone, as /notes is no longer a folder."),
        ]
        for (reason, message) in messages {
            #expect(UndoProblem(undoing: true, reason: reason).localizedDescription == message)
        }
        // The simulator runs in British English, where the Trash is the Bin.
        let trash = String(localized: "Trash")
        #expect(
            UndoProblem(undoing: true, reason: .notInBin("a")).localizedDescription
                == "This can't be undone, as a is no longer in the \(trash).")
        #expect(
            UndoProblem(undoing: false, reason: .notInBin("a")).localizedDescription
                == "This can't be redone, as a is no longer in the \(trash).")
    }

    @Test func asksAboutChangedItems() {
        let trash = String(localized: "Trash")
        #expect(
            UndoChanged(undoing: true, names: ["todo.txt"]).question
                == "todo.txt has changed since. Move it to the \(trash) anyway?")
        #expect(
            UndoChanged(undoing: true, names: ["a", "b"]).question
                == "2 items have changed since. Move them to the \(trash) anyway?")
    }

    @Test func saysHowFarItGot() {
        #expect(
            UndoRows.stoppedNote(undoing: true, done: 1, reason: "No space.")
                == "1 item was undone before Undo stopped. No space.")
        #expect(
            UndoRows.stoppedNote(undoing: false, done: 3, reason: "No space.")
                == "3 items were redone before Redo stopped. No space.")
    }
}
