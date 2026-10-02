import AppIntents
import SwiftUI
import WidgetKit

/// The launch actions as controls, for Control Center and the Action Button.
///
/// Each runs its intent, which opens the app; where a control goes is the
/// wearer's choice.
struct ResumeOrNewControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.iamrecursion.dialect.watch.resume-or-new") {
            ControlWidgetButton(action: ResumeOrNewSessionIntent()) {
                Label {
                    Text(LaunchRequest.resumeOrNew.title)
                } icon: {
                    Image(systemName: LaunchRequest.resumeOrNew.systemImage)
                }
            }
            .tint(Color(RGBColor.dialectGreen))
        }
        .displayName("Resume or New")
        .description("Opens your latest session, or a new one if there is none.")
    }
}

struct NewSessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.iamrecursion.dialect.watch.new-session") {
            ControlWidgetButton(action: NewSessionIntent()) {
                Label {
                    Text(LaunchRequest.new.title)
                } icon: {
                    Image(systemName: LaunchRequest.new.systemImage)
                }
            }
            .tint(Color(RGBColor.dialectGreen))
        }
        .displayName("New Session")
        .description("Opens a new session.")
    }
}
