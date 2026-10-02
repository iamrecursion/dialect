import SwiftUI

/// Settings > Credits (D13): a row for each of the notice's sections, then the
/// Apache License 2.0.
struct CreditsView: View {
    /// Parsed once, the first time Credits opens.
    private static let pages = NoticeDocument.creditsPages(in: .main)

    var body: some View {
        Group {
            if let pages = Self.pages {
                List {
                    PageLinks(pages: pages)
                }
            } else {
                Text("The credits could not be loaded.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Credits")
    }
}

/// One page of the credits: its blocks, then links to its subsections (the
/// license texts).
struct CreditsPageView: View {
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
    }
}

private struct PageLinks: View {
    let pages: [NoticeSection]

    var body: some View {
        ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
            NavigationLink(page.title, value: Route.creditsPage(page))
        }
    }
}

/// A block's list rows. Prose sits on the screen's background; each table row
/// is a card on the usual gray row.
private struct BlockRows: View {
    let block: NoticeBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(NoticeDocument.inline(text))
                .listRowBackground(Color.clear)
        case .plain(let text):
            Text(text)
                .font(.footnote)
                .listRowBackground(Color.clear)
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
        CreditsView()
    }
}
