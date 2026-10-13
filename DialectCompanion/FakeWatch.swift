#if DEBUG
    import Foundation

    /// For UI tests and screenshots: `-fakeWatch` and a state stand in for the
    /// session, with a snapshot unlike the defaults. Edits wait, as nothing
    /// applies them.
    enum FakeWatch {
        static let argument = "fakeWatch"

        /// The facts for the launch argument's state, if it has one.
        static func facts(in defaults: UserDefaults = .standard) -> LinkFacts? {
            switch defaults.string(forKey: argument) {
            case "connected": return facts(reachable: true)
            case "away": return facts(reachable: false)
            case "noSnapshot": return facts(snapshot: ReceivedSnapshot.none)
            case "unpaired":
                return LinkFacts(
                    isPaired: false, isWatchAppInstalled: false, isReachable: false,
                    snapshot: .none)
            case "notInstalled":
                return LinkFacts(
                    isPaired: true, isWatchAppInstalled: false, isReachable: false,
                    snapshot: .none)
            case "oldFormat": return facts(snapshot: .otherFormat(newer: false))
            default: return nil
            }
        }

        private static func facts(
            reachable: Bool = true, snapshot: ReceivedSnapshot = .readable(snapshot)
        ) -> LinkFacts {
            return LinkFacts(
                isPaired: true, isWatchAppInstalled: true, isReachable: reachable,
                snapshot: snapshot)
        }

        static let snapshot = SettingsSnapshot(
            epoch: "FAKE", settings: values.mapValues { .init(value: $0, version: 1) },
            undoSteps: 30, watchName: "Apple Watch Ultra")

        private static let values: [String: SettingValue] = [
            // The Purple swatch.
            AccentSetting.key: .string(RGBColor(sRGBRed: 0xBF, green: 0x5A, blue: 0xF2).displayP3),
            FileSettings.dateStyleKey: .string(DateStyle.iso.rawValue),
            FileSettings.use24HourKey: .bool(true),
            FileSettings.showExtensionsKey: .bool(false),
            FileSettings.showDetailsKey: .bool(true),
            FileSettings.relativeModifiedKey: .bool(false),
            FileSettings.foldersFirstKey: .bool(false),
            FileSettings.showHiddenKey: .bool(true),
            FileSettings.confirmExtensionChangesKey: .bool(false),
            FileSettings.textExtensionsKey: .strings(["fnl", "lisp", "rkt"]),
            FileSettings.emptyTrashAfterKey: .int(7),
            FileSettings.undoHistoryKey: .int(50),
            RecentsSettings.showLastKey: .int(10),
        ]
    }
#endif
