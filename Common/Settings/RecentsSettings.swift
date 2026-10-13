import Foundation

/// Settings › History.
enum RecentsSettings {
    static let showLastKey = "recents.showLast"
    static let showLastDefault = 5
    static let showLastChoices = [3, 5, 10, 20]

    static func showLast(in defaults: UserDefaults = .standard) -> Int {
        let count = defaults.integer(forKey: showLastKey)
        return count > 0 ? count : showLastDefault
    }
}

/// Recents' icons.
enum RecentsSymbol {
    static let recents = "clock.arrow.trianglehead.counterclockwise.rotate.90"
    static let showInFiles = "folder"
    static let hide = "eye.slash"
    static let pin = "pin"
    static let unpin = "pin.slash"
}
