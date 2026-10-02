import SwiftUI
import WidgetKit

/// A complication that opens Dialect with a launch request.
///
/// It takes its family so the app's debug gallery can draw every shape too.
struct LaunchComplicationView: View {
    let request: LaunchRequest
    let family: WidgetFamily

    /// One point at `.title3`, scaled with the icon.
    @ScaledMetric(relativeTo: .title3) private var point: CGFloat = 1

    var body: some View {
        content
            .widgetURL(request.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                icon
                    .font(.title3)
                VStack(alignment: .leading) {
                    Text(request.title)
                        .font(.headline)
                        // Shrinks a little rather than truncating "Resume or New".
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Text("Dialect")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                icon
                    .font(.title3)
            }
        }
    }

    /// The symbol, in Dialect's green on a full-color face and in the face's
    /// tint on a tinted one, nudged so it looks centered.
    private var icon: some View {
        Image(systemName: request.systemImage)
            .foregroundStyle(Color(RGBColor.dialectGreen))
            .offset(y: request.opticalOffset * point)
            .widgetAccentable()
    }
}

extension LaunchRequest {
    static let complicationFamilies: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular]
}
