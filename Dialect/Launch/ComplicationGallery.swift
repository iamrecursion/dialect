#if DEBUG
    import SwiftUI
    import WidgetKit

    /// Debug only: the complications drawn by the app, at about their size on a
    /// face, so their layout can be screenshotted. A face also tints them and
    /// curves the corner shape, which this cannot show: the real check is a
    /// watch face.
    struct ComplicationGallery: View {
        var body: some View {
            List {
                ForEach([LaunchRequest.resumeOrNew, .new], id: \.self) { request in
                    Section {
                        sample(request, .accessoryCircular, width: 50, height: 50)
                        sample(request, .accessoryRectangular, width: 160, height: 52)
                    } header: {
                        Text(request.title)
                    }
                }
                Section("Downloads") {
                    HStack(spacing: 16) {
                        DownloadsComplicationView(snapshot: .fake, family: .accessoryCircular)
                            .frame(width: 50, height: 50)
                        DownloadsComplicationView(snapshot: .fake, family: .accessoryCorner)
                            .frame(width: 32, height: 32)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Complications")
        }

        private func sample(
            _ request: LaunchRequest, _ family: WidgetFamily, width: CGFloat, height: CGFloat
        ) -> some View {
            return LaunchComplicationView(request: request, family: family)
                .frame(width: width, height: height)
                .listRowBackground(Color.clear)
        }
    }
#endif
