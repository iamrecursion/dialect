import SwiftUI

/// A value in a closed range, shown as a thumb on a gradient track, with its
/// value beside its name, designed to be set with the digital crown.
///
/// To enable scrolling, the user has to tap the slider to give it the crown's
/// focus, indicated by a border, while tapping it again removes that focus.
///
/// The crown moves the slider a step at a time, using the system's detent
/// haptic for each. Reaching the end plays a stronger haptic as an indicator.
struct CrownSlider: View {
    let title: LocalizedStringResource
    @Binding var value: Double

    /// Whether it has the crown. Owned by whatever holds several sliders, so
    /// that only one has it at a time. Only then is it focusable at all.
    @Binding var engaged: Bool

    let range: ClosedRange<Double>
    let step: Double

    /// Drawn along the track, from the range's lower end to its upper.
    let gradient: Gradient

    /// The value as shown beside the name.
    var readout: (Double) -> String = CrownSlider.percent

    /// The value as VoiceOver reads it.
    var describe: (Double) -> String = { "\(Int(($0 * 100).rounded())) percent" }

    @Environment(\.dialectAccent) private var accent
    @Environment(\.returnCrown) private var returnCrown
    @FocusState private var focused: Bool

    /// What the crown turns: the value times `crownScale`.
    @State private var crownValue: Double = 0

    /// Counts the end bump's pulses; each change plays one.
    @State private var pulses = 0

    /// The end bump: one strong pulse, then two lighter ones.
    private static let pulseSpacing = Duration.milliseconds(110)

    /// How many times more turning a step takes than the crown alone gives,
    /// which is too touchy for steps this fine.
    private static let crownScale = 10.0

    private static let trackHeight: CGFloat = 14
    private static let thumbSize: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(readout(value))
                    .monospacedDigit()
            }
            .font(.footnote)
            GeometryReader { geometry in
                let travel = geometry.size.width - Self.thumbSize
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: gradient, startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(height: Self.trackHeight)
                    Circle()
                        .strokeBorder(.white, lineWidth: engaged ? 3 : 2)
                        .background(Circle().fill(.black.opacity(0.25)))
                        .frame(width: Self.thumbSize, height: Self.thumbSize)
                        .offset(x: travel * fraction)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: Self.thumbSize + 8)
        }
        // More room above the name than around the rest: the list row's top inset is tight.
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(accent, lineWidth: 2)
                .opacity(engaged ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if engaged {
                // Released by a tap: the crown goes back to the page.
                engaged = false
                returnCrown?()
            } else {
                engaged = true
            }
        }
        .onDisappear { engaged = false }
        .focusable(engaged)
        .focused($focused)
        // Taking or releasing the crown moves the focus with it.
        .onChange(of: engaged) { focused = engaged }
        // Losing the focus some other way releases it.
        .onChange(of: focused) { if !focused && engaged { engaged = false } }
        // The crown turns a value of its own, `crownScale` times the real one, so a step takes that
        // many times more turning.
        .digitalCrownRotation(
            detent: $crownValue, from: range.lowerBound * Self.crownScale,
            through: range.upperBound * Self.crownScale, by: step * Self.crownScale,
            sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onAppear { crownValue = value * Self.crownScale }
        // Each follows the other only when they are at least half a step apart, which means one of
        // them really moved.
        .onChange(of: crownValue) {
            if isApart { value = Self.snapped(crownValue / Self.crownScale, to: step, in: range) }
        }
        .onChange(of: value) {
            if isApart { crownValue = value * Self.crownScale }
        }
        .onChange(of: value) { old, new in
            if Self.reachedEnd(from: old, to: new, in: range) { playEndBump() }
        }
        .sensoryFeedback(trigger: pulses) { _, count in
            // The first pulse of each three is the strong one.
            return count % 3 == 1 ? .impact(weight: .heavy) : .impact(weight: .light)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(title))
        .accessibilityValue(describe(value))
        // Selected while it has the crown, for VoiceOver (and tests).
        .accessibilityAddTraits(engaged ? .isSelected : [])
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    /// Whether the crown's value and the real one are at least half a step
    /// apart.
    private var isApart: Bool {
        return abs(crownValue / Self.crownScale - value) >= step / 2
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? (value - range.lowerBound) / span : 0
    }

    private func playEndBump() {
        Task {
            for pulse in 0..<3 {
                if pulse > 0 { try? await Task.sleep(for: Self.pulseSpacing) }
                pulses += 1
            }
        }
    }

    /// A value in `0...1` as a percentage: "41%".
    nonisolated static func percent(_ value: Double) -> String {
        return "\(Int((value * 100).rounded()))%"
    }

    /// A hue in `0...1` in degrees: "113°".
    nonisolated static func degrees(_ value: Double) -> String {
        return "\(Int((value * 360).rounded()))°"
    }

    /// `value` to the nearest whole `step` from the range's lower end, within
    /// the range: the crown's value, divided back down, can be a hair off a
    /// step.
    nonisolated static func snapped(_ value: Double, to step: Double, in range: ClosedRange<Double>)
        -> Double
    {
        let steps = ((value - range.lowerBound) / step).rounded()
        return min(max(range.lowerBound + steps * step, range.lowerBound), range.upperBound)
    }

    /// Whether moving from `old` to `new` arrives at either end of `range`: the
    /// end bump plays only on arriving.
    nonisolated static func reachedEnd(
        from old: Double, to new: Double, in range: ClosedRange<Double>
    ) -> Bool {
        return (new == range.lowerBound || new == range.upperBound) && new != old
    }
}

/// Gives the crown back to the page around a slider when the slider lets it go,
/// ensuring the crown can scroll the page again.
///
/// A type, so that SwiftUI can compare it: it can't compare a closure, so it
/// would treat every update as a change and redraw whatever reads it.
struct ReturnCrownAction: Equatable {
    let perform: @MainActor () -> Void

    @MainActor func callAsFunction() { perform() }

    static func == (_: ReturnCrownAction, _: ReturnCrownAction) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var returnCrown: ReturnCrownAction?
}
