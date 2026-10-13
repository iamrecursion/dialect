import Foundation

/// A fresh, empty store of settings, removed when the test is done with it.
final class TestDefaults: @unchecked Sendable {
    private let name = "DialectTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}
