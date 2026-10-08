import Foundation

@testable import Dialect

/// A root, separate stores, and operations on both.
struct OperationsSetup {
    let root: TemporaryRoot
    let stores: TemporaryRoot
    let sizes = FolderSizes()
    let operations: FileOperations

    init() throws {
        root = try TemporaryRoot()
        stores = try TemporaryRoot()
        operations = FileOperations(root: root.url, stores: stores.url, sizes: sizes)
    }

    var bin: Bin { Bin(url: FilesStores.bin(in: stores.url)) }
    var clipboard: Clipboard { Clipboard(url: FilesStores.clipboard(in: stores.url)) }
    var recents: Recents { Recents(url: FilesStores.recents(in: stores.url)) }
    var history: History { History(url: FilesStores.history(in: stores.url)) }

    func names(_ path: String = "") throws -> [String] {
        return try FileManager.default.contentsOfDirectory(
            atPath: root.url.appending(path: path).path(percentEncoded: false)
        ).sorted()
    }

    /// What's left in staging; nothing once each operation is done.
    func staged() -> [String] {
        let staging = FilesStores.staging(in: stores.url)
        return
            (try? FileManager.default.contentsOfDirectory(
                atPath: staging.path(percentEncoded: false))) ?? []
    }

    func text(_ path: String) throws -> String {
        return try String(contentsOf: root.url.appending(path: path), encoding: .utf8)
    }

    func exists(_ path: String) -> Bool {
        return (try? root.url.appending(path: path).resourceValues(forKeys: [.isSymbolicLinkKey]))
            != nil
    }
}

extension FilePath {
    /// A path written as `scripts/prelude.scm`; empty for the root.
    init(_ string: String) {
        self.init(components: string.split(separator: "/").map(String.init))
    }
}
