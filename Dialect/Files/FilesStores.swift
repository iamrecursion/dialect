import Foundation

/// Where Files keeps data that isn't the user's files.
enum FilesStores {
    /// The stores in use.
    @MainActor static var url = URL.applicationSupportDirectory.appending(
        path: "Files", directoryHint: .isDirectory)

    /// Where new items are made before they're renamed into place.
    static func staging(in stores: URL) -> URL {
        return stores.appending(path: "Staging", directoryHint: .isDirectory)
    }

    /// Where deleted items are kept until they expire.
    static func bin(in stores: URL) -> URL {
        return stores.appending(path: "Bin", directoryHint: .isDirectory)
    }
}
