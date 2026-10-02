import Testing

@testable import Dialect

struct CrownSliderTests {
    /// The end bump plays on arriving at an end, not while resting there or
    /// leaving it.
    @Test func bumpsOnReachingEitherEnd() {
        #expect(CrownSlider.reachedEnd(from: 0.1, to: 0, in: 0...1))
        #expect(CrownSlider.reachedEnd(from: 0.98, to: 1, in: 0...1))
        #expect(!CrownSlider.reachedEnd(from: 0, to: 0, in: 0...1))
        #expect(!CrownSlider.reachedEnd(from: 1, to: 0.98, in: 0...1))
        #expect(!CrownSlider.reachedEnd(from: 0.4, to: 0.5, in: 0...1))
    }

    /// The crown's own value, divided back down, lands on a whole step within
    /// the range.
    @Test func snapsTheCrownsValueToAStep() {
        #expect(abs(CrownSlider.snapped(0.6 + 1e-12, to: 0.01, in: 0...1) - 0.6) < 1e-12)
        #expect(abs(CrownSlider.snapped(0.604, to: 0.01, in: 0...1) - 0.6) < 1e-12)
        #expect(CrownSlider.snapped(1 + 1e-9, to: 0.01, in: 0...1) == 1)
        #expect(CrownSlider.snapped(-1e-9, to: 0.01, in: 0...1) == 0)
        let hue = CrownSlider.snapped(113.0 / 360 + 1e-12, to: 1.0 / 360, in: 0...1)
        #expect(abs(hue * 360 - 113) < 1e-9)
    }

    /// The readout beside each slider's name, so a color from elsewhere can be
    /// dialed in.
    @Test func readsOutPercentages() {
        #expect(CrownSlider.percent(0.41) == "41%")
        #expect(CrownSlider.percent(0) == "0%")
        #expect(CrownSlider.percent(1) == "100%")
        #expect(CrownSlider.percent(0.785) == "79%")
    }

    @Test func readsOutDegreesOfHue() {
        #expect(CrownSlider.degrees(113.0 / 360) == "113°")
        #expect(CrownSlider.degrees(0) == "0°")
        #expect(CrownSlider.degrees(1) == "360°")
    }
}
