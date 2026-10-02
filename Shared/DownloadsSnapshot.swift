import Foundation

/// What the downloads complication shows: how many downloads are running, and
/// how far the furthest-along one has got. Fake for now (`fake`); the
/// downloader will provide real ones.
struct DownloadsSnapshot: Hashable, Sendable {
    var running: Int
    /// The furthest-along download's progress, from 0 to 1.
    var furthestProgress: Double

    static let fake = DownloadsSnapshot(running: 3, furthestProgress: 0.62)

    var countText: String {
        return "\(running)"
    }

    /// The gauge's value: the furthest progress, clamped to 0 to 1, and empty
    /// when nothing is running.
    var gaugeValue: Double {
        return running > 0 ? min(max(furthestProgress, 0), 1) : 0
    }

    var progressText: String {
        return "\(Int((gaugeValue * 100).rounded()))%"
    }

    /// What VoiceOver reads.
    var accessibilityText: String {
        switch running {
        case 0: return "No downloads"
        case 1: return "1 download, at \(progressText)"
        default: return "\(running) downloads, the furthest at \(progressText)"
        }
    }
}
