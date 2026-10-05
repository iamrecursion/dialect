// TEMPORARY, TO BE REMOVED
#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// `-seedFiles`: Files' root moves to a fresh sample tree in the app's
    /// temporary directory, so UI tests and screenshots never touch real files.
    /// The tree holds every kind of item, a session, hidden items, a deep path,
    /// enough items to scroll, and modification dates in every Group by
    /// Modified bucket.
    enum SeedFiles {
        /// The launch argument.
        static let argument = "seedFiles"

        /// Where the sample root is built.
        static var root: URL {
            return FileManager.default.temporaryDirectory
                .appending(path: "SeedFiles/Documents", directoryHint: .isDirectory)
        }

        /// Where the sample stores go, beside the sample root, so the real bin
        /// is never touched.
        static var stores: URL {
            return FileManager.default.temporaryDirectory
                .appending(path: "SeedFiles/Application Support", directoryHint: .isDirectory)
        }

        /// Builds the tree at `root`, and the bin in `stores` when given,
        /// deleting whatever was in either first.
        static func build(at root: URL, stores: URL? = nil, now: Date = Date()) throws {
            let manager = FileManager.default
            try? manager.removeItem(at: root)
            try manager.createDirectory(at: root, withIntermediateDirectories: true)

            func write(_ path: String, _ contents: Data) throws {
                let url = root.appending(path: path, directoryHint: .notDirectory)
                try manager.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents.write(to: url)
            }
            func write(_ path: String, text: String) throws {
                try write(path, Data(text.utf8))
            }
            func folder(_ path: String) throws {
                try manager.createDirectory(
                    at: root.appending(path: path, directoryHint: .isDirectory),
                    withIntermediateDirectories: true)
            }

            try write("scripts/prelude.scm", text: "(define (square x) (* x x))\n")
            try write(
                "scripts/util.sld",
                text: "(define-library (util)\n  (export twice)\n  (import (scheme base))\n"
                    + "  (begin (define (twice f x) (f (f x)))))\n")
            try write("scripts/lib/a/b/c/d/deep.scm", text: "(display \"deep\")\n")

            try write("notes/notes.md", text: "# Notes\n\nThings to remember.\n")
            try write("notes/todo.txt", text: "- Write the file manager\n")
            try write("notes/config.toml", text: "[editor]\nindent = 2\n")
            try write("notes/data.json", text: "{\"answer\": 42}\n")
            try write("notes/table.csv", text: "name,count\nlambda,1\n")
            try write("notes/feed.xml", text: "<?xml version=\"1.0\"?>\n<feed/>\n")
            try write("notes/settings.yaml", text: "theme: dark\n")

            try write("media/photo.png", image(.png))
            try write("media/clip.mp4", Data())
            try write("media/Photo.JPG", image(.jpeg))

            try write("demo.dial/manifest.json", text: "{\"format\": 1}\n")
            try write("demo.dial/main.scm", text: "(display \"Hello from a session\")\n")

            for index in 1...12 {
                try write("many/file\(index).txt", text: "File \(index)\n")
            }

            try write(".hidden-config", text: "secret = true\n")
            try folder(".cache")
            try write("blob.bin", Data(0...255))
            try write("readme", text: "Dialect's sample files, for -seedFiles.\n")
            try folder("empty")

            // Last, since writing inside a folder changes its date.
            let hour: TimeInterval = 3600
            let ages: [TimeInterval] = [0, 30 * hour, 96 * hour, 240 * hour, 1440 * hour]
            let dated = [
                "notes/notes.md", "notes/todo.txt", "notes/config.toml", "notes/data.json",
                "notes/table.csv", "notes/feed.xml", "notes/settings.yaml",
                "scripts", "notes", "media", "demo.dial", "many", "blob.bin", "readme", "empty",
            ]
            for (index, path) in dated.enumerated() {
                let date = now - ages[index % ages.count]
                try manager.setAttributes(
                    [.modificationDate: date],
                    ofItemAtPath: root.appending(path: path).path(percentEncoded: false))
            }

            if let stores { try buildBin(in: stores, now: now) }
        }

        /// The bin, with what its tests need: an item to restore to its folder,
        /// one whose folder is gone, one whose place the root's `readme` has
        /// taken, two namesakes, and one the default 30 days has expired.
        private static func buildBin(in stores: URL, now: Date) throws {
            let manager = FileManager.default
            try? manager.removeItem(at: stores)
            let bin = Bin(url: FilesStores.bin(in: stores))
            let hour: TimeInterval = 3600
            let day = 24 * hour
            let items: [(name: String, original: String, age: TimeInterval, text: String)] = [
                ("readme", "readme", hour, "An older readme.\n"),
                ("old-notes.md", "notes/old-notes.md", 2 * day, "# Old notes\n"),
                ("draft.scm", "scripts/draft.scm", 3 * day, "(display \"second draft\")\n"),
                ("draft 2.scm", "scripts/draft.scm", 5 * day, "(display \"first draft\")\n"),
                ("sketch.scm", "gone/sketch.scm", 10 * day, "(display \"sketch\")\n"),
                ("expired.txt", "expired.txt", 40 * day, "Long gone.\n"),
            ]
            for item in items {
                let directory = bin.directory(for: UUID())
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                let original = item.original.split(separator: "/").map(String.init)
                try bin.write(
                    Bin.Record(name: item.name, original: original, deleted: now - item.age),
                    in: directory)
                try Data(item.text.utf8).write(to: Bin.item(in: directory))
            }
        }

        /// An 8×8 image in Dialect's green, drawn in code so no image file
        /// ships.
        private static func image(_ type: UTType) -> Data {
            let size = 8
            let data = NSMutableData()
            guard
                let context = CGContext(
                    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                let destination = CGImageDestinationCreateWithData(
                    data, type.identifier as CFString, 1, nil)
            else { return Data() }
            context.setFillColor(red: 0.57, green: 0.78, blue: 0.5, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            guard let image = context.makeImage() else { return Data() }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            return data as Data
        }
    }
#endif
