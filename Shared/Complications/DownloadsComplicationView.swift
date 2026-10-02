import SwiftUI
import WidgetKit

/// The downloads complication: how many downloads are running, and a gauge for
/// the furthest-along one. Circular: a ring around the count. Corner: the
/// count, with the gauge curving along the bezel. A tap opens the downloader
/// portion of the app.
struct DownloadsComplicationView: View {
    let snapshot: DownloadsSnapshot
    let family: WidgetFamily

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.accessibilityText)
            .widgetURL(LaunchRequest.downloader.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "arrow.down")
                .font(.title3)
                .foregroundStyle(green)
                .widgetAccentable()
                .widgetLabel {
                    Gauge(value: snapshot.gaugeValue) {
                        Text("Downloads")
                    } currentValueLabel: {
                        Text(snapshot.countText)
                    }
                    .tint(green)
                }
        default:
            // The with the count laid over its exact center: on a face, the gauge's own labels
            // pushed the count off center.
            Gauge(value: snapshot.gaugeValue) {
                EmptyView()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(green)
            .overlay {
                Text(snapshot.countText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    private var green: Color { Color(RGBColor.dialectGreen) }
}

extension DownloadsSnapshot {
    static let complicationFamilies: [WidgetFamily] = [.accessoryCircular, .accessoryCorner]
}
