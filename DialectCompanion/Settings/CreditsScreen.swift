import SwiftUI

/// Settings › Credits: the watch app's notice and license, a page for each of
/// the notice's sections.
struct CreditsScreen: View {
    /// Parsed once, the first time Credits opens.
    private static let pages = NoticeDocument.creditsPages(in: .main)

    var body: some View {
        Group {
            if let pages = Self.pages {
                List {
                    PageLinks(pages: pages)
                }
            } else {
                ContentUnavailableView(
                    "The credits could not be loaded.", systemImage: "list.clipboard")
            }
        }
        .navigationTitle("Credits")
    }
}

/// One page of the credits: its blocks, then links to its subsections (the
/// license texts).
struct CreditsPageScreen: View {
    let page: NoticeSection

    var body: some View {
        List {
            ForEach(Array(page.blocks.enumerated()), id: \.offset) { _, block in
                BlockRows(block: block)
            }
            if !page.subsections.isEmpty {
                Section {
                    PageLinks(pages: page.subsections)
                }
            }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PageLinks: View {
    let pages: [NoticeSection]

    var body: some View {
        ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
            NavigationLink(page.title) {
                CreditsPageScreen(page: page)
            }
        }
    }
}

/// A block's list rows: prose as plain rows, and a row for each of a table's
/// rows.
private struct BlockRows: View {
    let block: NoticeBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(NoticeDocument.inline(text))
        case .plain(let text):
            Text(text)
                .font(.footnote)
        case .table(let table):
            ForEach(Array(table.cards.enumerated()), id: \.offset) { _, card in
                VStack(alignment: .leading, spacing: 2) {
                    Text(NoticeDocument.inline(card.title))
                        .font(.headline)
                    ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                        Text(NoticeDocument.inline(line))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CreditsScreen()
    }
}
