import Foundation
import Testing

@testable import Dialect

/// The files the Credits screen reads must ship in the app bundle (D13).
struct BundleTests {
    @Test func bundlesTheNotice() throws {
        let url = try #require(Bundle.main.url(forResource: "NOTICE-dialect", withExtension: "md"))
        #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("# Third-party notices"))
    }

    @Test func bundlesTheLicense() throws {
        let url = try #require(Bundle.main.url(forResource: "LICENSE", withExtension: nil))
        #expect(try String(contentsOf: url, encoding: .utf8).contains("Apache License"))
    }

    /// The real files, parsed: catches the notice and the parser drifting
    /// apart. The counts are the notice's own: 14 Swift packages, 109
    /// third-party libraries, nine license texts.
    @Test func parsesTheBundledCredits() throws {
        let pages = try #require(NoticeDocument.creditsPages(in: .main))
        #expect(
            pages.map(\.title) == [
                "LispKit", "Swift packages", "highlight.js", "Bundled Scheme libraries",
                "Licence texts", "Apache License 2.0",
            ])
        #expect(
            pages[4].subsections.map(\.title) == [
                "BitByteData", "CBORCoding", "CommandLineKit", "Half", "highlight.js",
                "KeychainAccess", "NanoHTTP", "SWCompression", "ZIPFoundation",
            ])

        func tableRows(_ page: NoticeSection) -> [Int] {
            return page.blocks.compactMap { block in
                if case .table(let table) = block { return table.rows.count }
                return nil
            }
        }
        #expect(tableRows(pages[1]) == [14])
        #expect(tableRows(pages[3]) == [109])

        let holders = [
            "Copyright © 2018-2025 Google LLC",
            "Copyright © 2026 Matthias Zenger",
            "Copyright © 2017 Andy Best <andybest.net at gmail dot com>",
            "Copyright © 2010-2014 Salvatore Sanfilippo <antirez at gmail dot com>",
            "Copyright © 2010-2013 Pieter Noordhuis <pcnoordhuis at gmail dot com>",
        ]
        let commandLineKit = pages[4].subsections[2]
        #expect(commandLineKit.blocks.first == .plain(holders.joined(separator: "\n")))
        #expect(
            pages[5].blocks.first
                == .plain(
                    "Apache License Version 2.0, January 2004 http://www.apache.org/licenses/"))

        // No link survives anywhere.
        let all = pages + pages.flatMap(\.subsections)
        for block in all.flatMap(\.blocks) {
            if case .paragraph(let text) = block { #expect(!text.contains("](")) }
            if case .table(let table) = block {
                #expect(!table.rows.joined().contains { $0.contains("](") })
            }
        }
    }
}
