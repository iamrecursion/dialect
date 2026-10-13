import SwiftUI

/// The watch's Settings › Appearance › Accent Color: its swatches, then any
/// color from the system's picker.
struct AccentColorScreen: View {
    @Environment(PhoneLink.self) private var link

    var body: some View {
        let color = AccentSetting.color(from: link.value(AccentSetting.key)?.string ?? "")
        List {
            Section {
                ForEach(RGBColor.swatches) { swatch in
                    Button {
                        choose(swatch.color)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(swatch.color))
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)
                            Text(swatch.name)
                            Spacer()
                            if swatch.color == color {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    // A list's buttons draw in the tint; these are choices, drawn as the Settings
                    // app draws them.
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(swatch.color == color ? .isSelected : [])
                }
            } footer: {
                EditNote(key: AccentSetting.key)
            }
            Section {
                SwiftUI.ColorPicker(
                    "Custom",
                    selection: Binding(
                        get: { color.cgColor },
                        set: { chosen in RGBColor(cgColor: chosen).map(choose) }),
                    supportsOpacity: false)
            }
        }
        .navigationTitle("Accent Color")
    }

    private func choose(_ color: RGBColor) {
        link.edit(AccentSetting.key, to: .string(color.displayP3))
    }
}

#Preview {
    NavigationStack {
        AccentColorScreen()
    }
    .environment(PhoneLink())
}
