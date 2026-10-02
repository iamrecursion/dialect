import SwiftUI
import WidgetKit

/// Dialect's complications and controls.
@main
struct DialectWidgets: WidgetBundle {
    var body: some Widget {
        ResumeOrNewWidget()
        NewSessionWidget()
        DownloadsWidget()
        ResumeOrNewControl()
        NewSessionControl()
    }
}
