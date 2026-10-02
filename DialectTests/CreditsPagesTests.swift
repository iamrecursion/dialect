import Foundation
import Testing

@testable import Dialect

struct CreditsPagesTests {
    @Test func appendsTheApacheLicense() {
        let pages = NoticeDocument.creditsPages(
            notice: "## A\nText.",
            license: "\n      Apache License\n      Version 2.0\n\n   TERMS\n")
        #expect(pages?.map(\.title) == ["A", "Apache License 2.0"])
        #expect(pages?.last?.blocks == [.plain("Apache License Version 2.0"), .plain("TERMS")])
    }

    @Test func isNilWithoutEitherFile() {
        #expect(NoticeDocument.creditsPages(notice: nil, license: "x") == nil)
        #expect(NoticeDocument.creditsPages(notice: "## A", license: nil) == nil)
    }

    @Test func isNilWhenTheNoticeHasNoSections() {
        #expect(
            NoticeDocument.creditsPages(notice: "# Title\nOnly an introduction.", license: "x")
                == nil)
    }

    @Test func rendersInlineMarkdownWithoutItsMarkers() {
        let text = NoticeDocument.inline("**LispKit** and `(lispkit clos)`")
        #expect(String(text.characters) == "LispKit and (lispkit clos)")
    }
}
