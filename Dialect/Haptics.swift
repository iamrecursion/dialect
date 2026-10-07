import WatchKit

/// Dialect's taps: short runs of the system's, as watchOS can't play custom
/// patterns.
@MainActor
enum Haptics {
    /// Rising: a click, Direction Up, then Start.
    static func undo() {
        play([.click, .directionUp, .start], gap: .milliseconds(150))
    }

    /// The same as Undo.
    static func redo() {
        play([.click, .directionUp, .start], gap: .milliseconds(150))
    }

    /// A click, then Retry, as a Delete Permanently confirmation appears.
    static func confirmPermanentDeletion() {
        play([.click, .retry], gap: .milliseconds(200))
    }

    private static func play(_ types: [WKHapticType], gap: Duration) {
        Task {
            for (index, type) in types.enumerated() {
                if index > 0 { try? await Task.sleep(for: gap) }
                WKInterfaceDevice.current().play(type)
            }
        }
    }
}
