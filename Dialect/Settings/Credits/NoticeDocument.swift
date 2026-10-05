import Foundation

/// `NOTICE-dialect.md`, parsed for the Credits screen.
///
/// The notice uses only headings, paragraphs, tables and fenced code blocks,
/// with links, bold and code spans inline. Anything else degrades to
/// paragraphs.
///
/// We parse the file at runtime to avoid a mismatch between the file and the
/// display of the notices.
struct NoticeDocument: Hashable, Sendable {
    /// The `##` sections, in order. The `#` heading and the introduction under
    /// it are dropped as they describe the file.
    var sections: [NoticeSection]
}

/// A `##` section, or a `###` subsection of one.
struct NoticeSection: Hashable, Sendable {
    var title: String
    var blocks: [NoticeBlock]

    /// The `###` subsections. Only "Licence texts" has any.
    var subsections: [NoticeSection]
}

enum NoticeBlock: Hashable, Sendable {
    /// Prose with inline Markdown (bold, code spans). Links are already reduced
    /// to their text.
    case paragraph(String)

    /// One reflowed paragraph of a license text, shown as is with no Markdown.
    case plain(String)

    case table(NoticeTable)
}

struct NoticeTable: Hashable, Sendable {
    var headers: [String]
    /// Every row has exactly `headers.count` cells.
    var rows: [[String]]

    /// The rows as stacked cards, since four columns do not fit on a watch: the
    /// first cell is the title, and each other non-empty cell a line labeled by
    /// its column's header.
    var cards: [NoticeCard] {
        return rows.map { row in
            let lines = zip(headers, row).dropFirst().filter { !$0.1.isEmpty }.map {
                "\($0): \($1)"
            }
            return NoticeCard(title: row.first ?? "", lines: lines)
        }
    }
}

struct NoticeCard: Hashable, Sendable {
    var title: String
    var lines: [String]
}

extension NoticeDocument {
    init(markdown: String) {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var sections: [NoticeSection] = []
        // False while in the dropped `#` part, and until the first `##`.
        var inSection = false
        for chunk in Self.chunks(lines) {
            switch chunk.level {
            case 2:
                sections.append(
                    NoticeSection(
                        title: chunk.title, blocks: Self.blocks(chunk.body), subsections: []))
                inSection = true
            case 3...:
                guard inSection else { continue }
                sections[sections.count - 1].subsections.append(
                    NoticeSection(
                        title: chunk.title, blocks: Self.blocks(chunk.body), subsections: []))
            default:
                inSection = false
            }
        }
        self.init(sections: sections)
    }

    /// Lines of a license text, reflowed for a narrow screen: the lines of each
    /// paragraph (blank-line separated) are joined with spaces, except that a
    /// line starting with "Copyright" stays on its own line. Indentation is
    /// dropped but every word is kept.
    static func reflow(_ lines: [String]) -> [String] {
        var paragraphs: [String] = []
        var current = ""
        for line in lines {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                if !current.isEmpty { paragraphs.append(current) }
                current = ""
            } else if current.isEmpty {
                current = text
            } else {
                current += (text.hasPrefix("Copyright") ? "\n" : " ") + text
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs
    }

    private struct Chunk {
        /// The heading's level; the text before the first heading is level 1,
        /// like the `#` part.
        var level: Int
        var title: String
        var body: [String]
    }

    /// Splits the lines at headings. A closed code block is kept whole, so a
    /// `#` line inside one stays text.
    private static func chunks(_ lines: [String]) -> [Chunk] {
        var chunks = [Chunk(level: 1, title: "", body: [])]
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if isFence(line), let close = lines[(index + 1)...].firstIndex(where: isFence) {
                chunks[chunks.count - 1].body += lines[index...close]
                index = close + 1
                continue
            }
            if let (level, title) = heading(line) {
                chunks.append(Chunk(level: level, title: title, body: []))
            } else {
                chunks[chunks.count - 1].body.append(line)
            }
            index += 1
        }
        return chunks
    }

    private static func blocks(_ lines: [String]) -> [NoticeBlock] {
        var blocks: [NoticeBlock] = []
        var paragraph: [String] = []
        func endParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(withoutLinks(paragraph.joined(separator: " "))))
            paragraph = []
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                endParagraph()
                index += 1
            } else if isFence(line), let close = lines[(index + 1)...].firstIndex(where: isFence) {
                endParagraph()
                blocks += reflow(Array(lines[(index + 1)..<close])).map(NoticeBlock.plain)
                index = close + 1
            } else if text.hasPrefix("|"), index + 1 < lines.count, isSeparator(lines[index + 1]) {
                endParagraph()
                let headers = cells(line)
                var rows: [[String]] = []
                index += 2
                while index < lines.count,
                    lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|")
                {
                    let row = cells(lines[index])
                    rows.append(
                        Array(row.prefix(headers.count))
                            + Array(repeating: "", count: max(0, headers.count - row.count)))
                    index += 1
                }
                blocks.append(.table(NoticeTable(headers: headers, rows: rows)))
            } else {
                paragraph.append(text)
                index += 1
            }
        }
        endParagraph()
        return blocks
    }

    private static func isFence(_ line: String) -> Bool {
        return line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    /// `(level, title)` for an ATX heading (`#` to `######`, then a space),
    /// else `nil`.
    private static func heading(_ line: String) -> (Int, String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
        return (level, line.dropFirst(level).trimmingCharacters(in: .whitespaces))
    }

    /// A table's separator row, such as `| --- | :-: |`.
    private static func isSeparator(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        return text.hasPrefix("|") && text.contains("-") && text.allSatisfy { "|-: ".contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.split(separator: "|", omittingEmptySubsequences: false).map {
            withoutLinks($0.trimmingCharacters(in: .whitespaces))
        }
    }

    /// `[text](destination)` becomes `text`: the notice's in-file anchors can't
    /// work in the app, and Credits doesn't link out to the web.
    private static func withoutLinks(_ text: String) -> String {
        return text.replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.output.1) }
    }
}

extension NoticeDocument {
    /// The Credits screen's pages, read from the app bundle. `nil` if either
    /// file is missing or unreadable; see `creditsPages(notice:license:)`.
    static func creditsPages(in bundle: Bundle) -> [NoticeSection]? {
        func read(_ name: String, _ ext: String?) -> String? {
            guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return creditsPages(notice: read("NOTICE-dialect", "md"), license: read("LICENSE", nil))
    }

    /// The notice's sections, then the Apache License 2.0 (`LICENSE`, reflowed)
    /// as a page of its own. `nil` if a file is missing or the notice has no
    /// sections.
    static func creditsPages(notice: String?, license: String?) -> [NoticeSection]? {
        guard let notice, let license else { return nil }
        let sections = NoticeDocument(markdown: notice).sections
        guard !sections.isEmpty else { return nil }
        let apache = NoticeSection(
            title: "Apache License 2.0",
            blocks: reflow(license.components(separatedBy: "\n")).map(NoticeBlock.plain),
            subsections: [])
        return sections + [apache]
    }

    /// A paragraph's or a cell's inline Markdown, rendered: bold and code
    /// spans. Falls back to the text as is if it does not parse.
    static func inline(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options))
            ?? AttributedString(markdown)
    }
}
