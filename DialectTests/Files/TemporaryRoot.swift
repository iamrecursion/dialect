import Foundation

/// A fresh directory standing in for Files' root, removed when the test is done
/// with it.
final class TemporaryRoot: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "FilesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes a file at a path relative to the root, making its folders.
    @discardableResult
    func file(_ path: String, _ contents: Data = Data()) throws -> URL {
        let file = url.appending(path: path, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file)
        return file
    }

    @discardableResult
    func file(_ path: String, text: String) throws -> URL {
        return try file(path, Data(text.utf8))
    }

    /// Makes a folder at a path relative to the root, and its parents.
    @discardableResult
    func folder(_ path: String) throws -> URL {
        let folder = url.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
