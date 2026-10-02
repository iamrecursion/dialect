import SwiftUI
import WidgetKit

/// A launch complication's one entry: it never changes, it only opens the app.
struct LaunchEntry: TimelineEntry {
    let date: Date
    let request: LaunchRequest
}

struct LaunchProvider: TimelineProvider {
    let request: LaunchRequest

    func placeholder(in context: Context) -> LaunchEntry {
        return LaunchEntry(date: .now, request: request)
    }

    func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}

/// Reads the family a face gives it, which `LaunchComplicationView` takes as a
/// parameter.
struct LaunchWidgetView: View {
    let entry: LaunchEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LaunchComplicationView(request: entry.request, family: family)
            .containerBackground(.clear, for: .widget)
    }
}

struct ResumeOrNewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "resume-or-new", provider: LaunchProvider(request: .resumeOrNew))
        {
            LaunchWidgetView(entry: $0)
        }
        .configurationDisplayName("Resume or New")
        .description("Opens your latest session, or a new one if there is none.")
        .supportedFamilies(LaunchRequest.complicationFamilies)
    }
}

struct NewSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "new-session", provider: LaunchProvider(request: .new)) {
            LaunchWidgetView(entry: $0)
        }
        .configurationDisplayName("New Session")
        .description("Opens a new session.")
        .supportedFamilies(LaunchRequest.complicationFamilies)
    }
}

#Preview(as: .accessoryCircular) {
    ResumeOrNewWidget()
} timeline: {
    LaunchEntry(date: .now, request: .resumeOrNew)
}

#Preview(as: .accessoryRectangular) {
    ResumeOrNewWidget()
} timeline: {
    LaunchEntry(date: .now, request: .resumeOrNew)
}
