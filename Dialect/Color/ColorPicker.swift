import SwiftUI

/// Chooses a color: a preview, swatches, hue, saturation and brightness
/// sliders, a hex field (sRGB, as hex is everywhere else) and a reset. It does
/// not know where the color is stored: it edits a binding.
///
/// While it is on screen the sliders keep their own hue, saturation and
/// brightness, and the color follows the settings. Deriving them from the color
/// each time would make them jitter (each component is rounded) and would lose
/// the hue of a gray. A swatch, a hex value or a reset sets the color, and the
/// sliders are derived from it as a one-off.
struct ColorPicker<Preview: View>: View {
    @Binding var color: RGBColor

    /// What Reset to Default restores.
    let defaultColor: RGBColor
    var swatches: [NamedColor] = RGBColor.swatches

    /// The first row: whatever shows the color best where it is used.
    @ViewBuilder let preview: (Color) -> Preview

    /// The slider that has the crown, if any: one at a time.
    @State private var engaged: WritableKeyPath<HSB, Double>?

    /// The sliders' values; `nil` until first shown. Whether the page has the
    /// crown, so that it scrolls when no slider is taking it.
    @FocusState private var pageHasCrown: Bool
    @State private var sliders: HSB?
    @State private var hexText = ""
    @State private var hexRejected = false
    @State private var showsHexDifference = false

    private var hsb: HSB { sliders ?? color.hsb(fallbackHue: 0) }

    var body: some View {
        List {
            // One section, so the swatches sit the usual row gap from the preview below them.
            Section {
                swatchGrid
                    // As much room below the swatches as the title leaves above them (measured
                    // within 2 px on the 42 mm and the Ultra).
                    .padding(.bottom, 5)
                    .listRowBackground(Color.clear)
                // Beside the sliders, where the eye is while dialing a color in.
                preview(Color(color))
                CrownSlider(
                    title: "Hue", value: slider(\.hue), engaged: engagement(\.hue), range: 0...1,
                    step: 1.0 / 360,
                    gradient: Gradient(
                        colors: stride(from: 0.0, through: 1, by: 1.0 / 6).map {
                            Color(RGBColor(HSB(hue: $0, saturation: 1, brightness: 1)))
                        }),
                    readout: CrownSlider.degrees,
                    describe: { "\(Int(($0 * 360).rounded())) degrees" })
                CrownSlider(
                    title: "Saturation", value: slider(\.saturation),
                    engaged: engagement(\.saturation), range: 0...1, step: 0.01,
                    gradient: gradient {
                        HSB(hue: $0.hue, saturation: $1, brightness: $0.brightness)
                    })
                CrownSlider(
                    title: "Brightness", value: slider(\.brightness),
                    engaged: engagement(\.brightness), range: 0...1, step: 0.01,
                    gradient: gradient {
                        HSB(hue: $0.hue, saturation: $0.saturation, brightness: $1)
                    })
            }
            Section {
                TextField("Hex", text: $hexText)
                    .onSubmit(applyHex)
                    // Over the field, so the field keeps its look and the rest of it its taps.
                    .overlay(alignment: .trailing) {
                        if !color.isWithinSRGB {
                            hexWarning
                        }
                    }
                if hexRejected {
                    Text("Use a hex color like \(defaultColor.hex)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            } header: {
                Text("Hex")
            }
            Button("Reset to Default") { choose(defaultColor) }
                .disabled(color == defaultColor)
        }
        .focused($pageHasCrown)
        .environment(\.returnCrown, ReturnCrownAction { pageHasCrown = true })
        .onAppear {
            sliders = sliders ?? color.hsb(fallbackHue: 0)
            hexText = color.hex
        }
        .onChange(of: color) { hexText = color.hex }
    }

    /// Beside a hex value that is only the nearest to the color; brings up the
    /// difference.
    private var hexWarning: some View {
        Button {
            showsHexDifference = true
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hex Not Exact")
        .fullScreenCover(isPresented: $showsHexDifference) {
            HexDifference(color: color) { showsHexDifference = false }
        }
    }

    private var swatchGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            ForEach(swatches) { swatch in
                Button {
                    choose(swatch.color)
                } label: {
                    Circle()
                        .fill(Color(swatch.color))
                        .overlay {
                            if swatch.color == color {
                                Circle().strokeBorder(.white, lineWidth: 3)
                            }
                        }
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(swatch.name))
                .accessibilityAddTraits(swatch.color == color ? .isSelected : [])
            }
        }
    }

    /// Whether a slider has the crown. Taking it takes it from the others;
    /// letting it go leaves any other slider's alone.
    private func engagement(_ component: WritableKeyPath<HSB, Double>) -> Binding<Bool> {
        return Binding(
            get: { engaged == component },
            set: { on in
                if on {
                    engaged = component
                } else if engaged == component {
                    engaged = nil
                }
            })
    }

    /// A binding to one of the sliders' values, which sets the color too.
    private func slider(_ component: WritableKeyPath<HSB, Double>) -> Binding<Double> {
        return Binding(
            get: { hsb[keyPath: component] },
            set: { value in
                var next = hsb
                next[keyPath: component] = value
                sliders = next
                color = RGBColor(next)
            })
    }

    /// A slider's track: the color across its whole range, the other two
    /// components held.
    private func gradient(_ at: @escaping (HSB, Double) -> HSB) -> Gradient {
        let current = hsb
        return Gradient(
            colors: stride(from: 0.0, through: 1, by: 0.25).map {
                Color(RGBColor(at(current, $0)))
            })
    }

    private func choose(_ chosen: RGBColor) {
        color = chosen
        sliders = chosen.hsb(fallbackHue: hsb.hue)
        hexRejected = false
    }

    private func applyHex() {
        if let applied = color.applyingHex(hexText) {
            choose(applied)
            hexText = applied.hex
        } else {
            hexRejected = true
            hexText = color.hex
        }
    }
}

/// What the hex warning brings up: the color beside the nearest that hex can
/// show, and Okay to dismiss it.
private struct HexDifference: View {
    let color: RGBColor
    let dismiss: () -> Void

    /// How much of the top safe area is the navigation bar's.
    private static let hiddenBarHeight: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(.top, max(proxy.safeAreaInsets.top - Self.hiddenBarHeight, 0))
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        // Okay is the way out, as in a notification, so not the system's close button too.
        .toolbar(.hidden, for: .navigationBar)
    }

    private var content: some View {
        VStack(spacing: 12) {
            // A notification's platter.
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 0) {
                    half(Color(color), label: Text("Chosen"), side: .leading)
                    half(
                        Color(color.nearestInSRGB), label: Text(verbatim: color.hex),
                        side: .trailing)
                }
                Text("More vivid than sRGB hex can represent.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .glassEffect(in: RoundedRectangle(cornerRadius: 24))
            Button("Okay", action: dismiss)
        }
    }

    /// One side of the comparison: the two meet in the middle, so the
    /// difference shows at the seam.
    private func half(_ fill: Color, label: Text, side: HorizontalEdge) -> some View {
        let radius: CGFloat = 12
        return VStack(spacing: 4) {
            UnevenRoundedRectangle(
                topLeadingRadius: side == .leading ? radius : 0,
                bottomLeadingRadius: side == .leading ? radius : 0,
                bottomTrailingRadius: side == .trailing ? radius : 0,
                topTrailingRadius: side == .trailing ? radius : 0
            )
            .fill(fill)
            .frame(height: 40)
            label
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
