import SwiftUI
import WidgetKit

struct DownloadsEntry: TimelineEntry {
    let date: Date
    let snapshot: DownloadsSnapshot
}

/// Fake data for now: one entry that never changes. The downloader will provide
/// real snapshots (through an App Group) and ask WidgetKit to reload.
struct DownloadsProvider: TimelineProvider {
    func placeholder(in context: Context) -> DownloadsEntry {
        return DownloadsEntry(date: .now, snapshot: .fake)
    }

    func getSnapshot(in context: Context, completion: @escaping (DownloadsEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DownloadsEntry>) -> Void)
    {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}

struct DownloadsWidgetView: View {
    let entry: DownloadsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        DownloadsComplicationView(snapshot: entry.snapshot, family: family)
            .containerBackground(.clear, for: .widget)
    }
}

struct DownloadsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "downloads", provider: DownloadsProvider()) {
            DownloadsWidgetView(entry: $0)
        }
        .configurationDisplayName("Downloads")
        .description("How many downloads are running, and how far the furthest has got.")
        .supportedFamilies(DownloadsSnapshot.complicationFamilies)
    }
}

#Preview(as: .accessoryCircular) {
    DownloadsWidget()
} timeline: {
    DownloadsEntry(date: .now, snapshot: .fake)
    DownloadsEntry(date: .now, snapshot: DownloadsSnapshot(running: 0, furthestProgress: 0))
}

#Preview(as: .accessoryCorner) {
    DownloadsWidget()
} timeline: {
    DownloadsEntry(date: .now, snapshot: .fake)
}
