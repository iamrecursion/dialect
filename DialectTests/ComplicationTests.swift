import Testing
import WidgetKit

@testable import Dialect

struct ComplicationTests {
    /// The launch icons look wrong curved into a corner or as a line of text,
    /// so they're circular and rectangular only.
    @Test func launchComplicationsAreCircularAndRectangular() {
        #expect(LaunchRequest.complicationFamilies == [.accessoryCircular, .accessoryRectangular])
    }

    /// The downloads gauge does look good curved into a corner.
    @Test func theDownloadsComplicationIsCircularAndCorner() {
        #expect(DownloadsSnapshot.complicationFamilies == [.accessoryCircular, .accessoryCorner])
    }

    /// `square.and.pencil`'s pencil tip sticks up above its square, so the
    /// square sits low in a circle; nudged up as on the menu (measured at
    /// `.title3`).
    @Test func newSessionsSquareSitsInTheMiddle() {
        #expect(LaunchRequest.new.opticalOffset == -1.5)
        #expect(LaunchRequest.resumeOrNew.opticalOffset == 0)
        #expect(LaunchRequest.downloader.opticalOffset == 0)
    }
}
