import Testing

@testable import Dialect

struct NoticeDocumentTests {
    @Test func dropsTheTitleAndIntroduction() {
        let document = NoticeDocument(
            markdown: """
                # Third-party notices

                This file credits everything.

                ## LispKit

                Body.
                """)
        #expect(document.sections.map(\.title) == ["LispKit"])
        #expect(document.sections[0].blocks == [.paragraph("Body.")])
    }

    @Test func nestsLevelThreeHeadingsUnderTheirSection() {
        let document = NoticeDocument(
            markdown: """
                ## A
                ## Licence texts
                Reproduced verbatim.
                ### One
                ### Two
                """)
        #expect(document.sections.map(\.title) == ["A", "Licence texts"])
        #expect(document.sections[1].blocks == [.paragraph("Reproduced verbatim.")])
        #expect(document.sections[1].subsections.map(\.title) == ["One", "Two"])
    }

    @Test func dropsSubsectionsBeforeAnySection() {
        let document = NoticeDocument(markdown: "# T\n### Orphan\ntext\n## A\nBody.")
        #expect(document.sections.map(\.title) == ["A"])
        #expect(document.sections[0].subsections.isEmpty)
    }

    @Test func joinsParagraphLines() {
        let document = NoticeDocument(markdown: "## A\nfirst line\n  second line\n\nnext")
        #expect(
            document.sections[0].blocks == [
                .paragraph("first line second line"), .paragraph("next"),
            ])
    }

    @Test func reducesLinksToTheirText() {
        let document = NoticeDocument(
            markdown: "## A\nSee **[LispKit](https://x.y) 2.6** and [`LICENSE`](LICENSE).")
        #expect(document.sections[0].blocks == [.paragraph("See **LispKit 2.6** and `LICENSE`.")])
    }

    @Test func parsesTables() {
        let document = NoticeDocument(
            markdown: """
                ## A
                | Package           | Version | License       |
                | ----------------- | ------- | ------------- |
                | [Half](https://h) | 1.4.2   |  MIT          |
                | `(lispkit clos)`  |         | Xerox license |
                After.
                """)
        let table = NoticeTable(
            headers: ["Package", "Version", "License"],
            rows: [["Half", "1.4.2", "MIT"], ["`(lispkit clos)`", "", "Xerox license"]])
        #expect(document.sections[0].blocks == [.table(table), .paragraph("After.")])
    }

    @Test func fitsRowsToTheHeader() {
        let document = NoticeDocument(markdown: "## A\n| a | b |\n| - | - |\n| 1 |\n| 1 | 2 | 3 |")
        let table = NoticeTable(headers: ["a", "b"], rows: [["1", ""], ["1", "2"]])
        #expect(document.sections[0].blocks == [.table(table)])
    }

    @Test func turnsRowsIntoCardsWithoutEmptyCells() {
        let table = NoticeTable(
            headers: ["Package", "Version", "License"],
            rows: [["Half", "1.4.2", "MIT"], ["clos", "", "Xerox"]])
        #expect(
            table.cards == [
                NoticeCard(title: "Half", lines: ["Version: 1.4.2", "License: MIT"]),
                NoticeCard(title: "clos", lines: ["License: Xerox"]),
            ])
    }

    @Test func reflowsCodeBlocks() {
        let document = NoticeDocument(
            markdown: """
                ## A
                ```text
                MIT License

                Permission is hereby granted, free of charge, to any person
                  obtaining a copy of this software.
                ```
                """)
        #expect(
            document.sections[0].blocks == [
                .plain("MIT License"),
                .plain(
                    "Permission is hereby granted, free of charge, to any person obtaining a copy of"
                        + " this software."),
            ])
    }

    @Test func keepsEachCopyrightLineOnItsOwnLine() {
        let lines = [
            "Copyright © 2024 Matthias Zenger", "Copyright © 2014 Damian Kołakowski", "",
            "Redistribution and use", "are permitted.",
        ]
        #expect(
            NoticeDocument.reflow(lines) == [
                "Copyright © 2024 Matthias Zenger\nCopyright © 2014 Damian Kołakowski",
                "Redistribution and use are permitted.",
            ])
    }

    @Test func treatsHeadingsInCodeBlocksAsText() {
        let document = NoticeDocument(markdown: "## A\n```\n## not a heading\n```\n## B")
        #expect(document.sections.map(\.title) == ["A", "B"])
        #expect(document.sections[0].blocks == [.plain("## not a heading")])
    }

    @Test func degradesATableWithoutSeparatorToAParagraph() {
        let document = NoticeDocument(markdown: "## A\n| a | b |\n| c | d |")
        #expect(document.sections[0].blocks == [.paragraph("| a | b | | c | d |")])
    }

    @Test func degradesAnUnclosedCodeBlockToParagraphs() {
        let document = NoticeDocument(markdown: "## A\n```text\nsome text\n## B\nmore")
        #expect(document.sections.map(\.title) == ["A", "B"])
        #expect(document.sections[0].blocks == [.paragraph("```text some text")])
        #expect(document.sections[1].blocks == [.paragraph("more")])
    }

    @Test func acceptsWindowsLineEndings() {
        let document = NoticeDocument(markdown: "## A\r\nline one\r\nline two\r\n")
        #expect(document.sections.map(\.title) == ["A"])
        #expect(document.sections[0].blocks == [.paragraph("line one line two")])
    }
}
