import SwiftUI
import UIKit

/// The watch's connection to the phone, and what it means for Settings.
struct WatchScreen: View {
    @Environment(PhoneLink.self) private var link

    var body: some View {
        List {
            if let status = link.status {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "applewatch")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: link.watchName)
                                .font(.headline)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                StatusDot(connected: status == .connected)
                                Text(Self.title(of: status))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text(Self.explanation(of: status))
                }
            }
        }
        .navigationTitle("Watch")
    }

    static func title(of status: LinkStatus) -> LocalizedStringResource {
        switch status {
        case .connected: return "Connected"
        case .away: return "Not Connected"
        case .unpaired: return "Not Paired"
        case .notInstalled: return "Dialect Not Installed"
        case .noSnapshot: return "Waiting for Dialect"
        case .otherFormat: return "Update Needed"
        }
    }

    static func explanation(of status: LinkStatus) -> LocalizedStringResource {
        switch status {
        case .connected:
            return
                "Dialect is open on your watch. Changes to its settings show in Settings as they happen."
        case .away:
            return """
                Dialect isn't open on your watch, or the watch is out of reach. Settings shows \
                them as the watch last sent them, and updates when Dialect next opens.
                """
        case .unpaired:
            return """
                This iPhone isn't paired with an Apple Watch. Pair one in the Watch app to see \
                Dialect's settings in Settings.
                """
        case .notInstalled:
            return """
                Dialect isn't installed on your watch. Install it from the Watch app on this \
                iPhone, then open it on the watch once.
                """
        case .noSnapshot:
            return "Open Dialect on your watch once, and its settings will show in Settings."
        case .otherFormat(let watchIsNewer):
            return watchIsNewer
                ? """
                Dialect on your watch is newer than on this iPhone. Update Dialect on this \
                iPhone to see your watch's settings.
                """
                : """
                Dialect on this iPhone is newer than on your watch. Update Dialect on your watch \
                to see its settings in Settings.
                """
        }
    }
}

/// Green while Dialect is open on the watch, red otherwise. A glyph in the
/// text, so it sits on the line and scales with it; hollow when not connected
/// if the user asks for differences shown without color.
private struct StatusDot: View {
    let connected: Bool

    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor

    var body: some View {
        Text(Image(systemName: connected || !withoutColor ? "circle.fill" : "circle"))
            .font(.caption2)
            .foregroundStyle(connected ? .green : .red)
            .accessibilityHidden(true)
    }
}

/// The Watch tab's icon: the watch, with a green dot while Dialect is open on
/// it and a red one otherwise (hollow if the user asks for differences shown
/// without color). A tab bar tints its icons in one color, so this icon is
/// drawn already colored, the watch as the tab bar would tint it.
enum WatchTabIcon {
    static func image(
        connected: Bool, selected: Bool, withoutColor: Bool, tint: UIColor,
        traits: UITraitCollection
    ) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: 20)
        guard let symbol = UIImage(systemName: "applewatch", withConfiguration: configuration)
        else { return UIImage() }
        let dot: CGFloat = 8
        let size = CGSize(width: symbol.size.width + dot / 2, height: symbol.size.height)
        let format = UIGraphicsImageRendererFormat(for: traits)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let watch = selected ? tint : UIColor.label
            symbol.withTintColor(watch.resolvedColor(with: traits)).draw(at: .zero)
            let color = (connected ? UIColor.systemGreen : UIColor.systemRed)
                .resolvedColor(with: traits)
            let rect = CGRect(x: size.width - dot, y: 0, width: dot, height: dot)
            if connected || !withoutColor {
                color.setFill()
                UIBezierPath(ovalIn: rect).fill()
            } else {
                color.setStroke()
                let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                ring.stroke()
            }
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

#Preview {
    NavigationStack {
        WatchScreen()
    }
    .environment(PhoneLink())
}
