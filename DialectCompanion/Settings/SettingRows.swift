import SwiftUI

/// An on/off setting of the watch's.
struct SettingToggle: View {
    @Environment(PhoneLink.self) private var link
    let title: LocalizedStringResource
    let key: String

    var body: some View {
        if let value = link.value(key)?.bool {
            Toggle(isOn: Binding(get: { value }, set: { link.edit(key, to: .bool($0)) })) {
                SettingTitle(title: title, key: key)
            }
        }
    }
}

/// A setting of the watch's with a choice of values. A value that isn't one of
/// the choices is shown too.
struct SettingPicker<Value: SettingChoice>: View {
    @Environment(PhoneLink.self) private var link
    let title: LocalizedStringResource
    let key: String
    let choices: [Value]

    /// What choosing a value does, if not changing the setting at once.
    var choose: ((Value) -> Void)?
    let label: (Value) -> Text

    var body: some View {
        if let value = link.value(key).flatMap(Value.init(setting:)) {
            Picker(
                selection: Binding(
                    get: { value },
                    set: { chosen in
                        if let choose {
                            choose(chosen)
                        } else {
                            link.edit(key, to: chosen.setting)
                        }
                    })
            ) {
                ForEach(choices.contains(value) ? choices : choices + [value], id: \.self) {
                    label($0).tag($0)
                }
            } label: {
                SettingTitle(title: title, key: key)
            }
        }
    }
}

/// A value a setting's picker offers.
protocol SettingChoice: Hashable {
    init?(setting: SettingValue)
    var setting: SettingValue { get }
}

extension Bool: SettingChoice {
    init?(setting: SettingValue) {
        guard let value = setting.bool else { return nil }
        self = value
    }

    var setting: SettingValue { .bool(self) }
}

extension Int: SettingChoice {
    init?(setting: SettingValue) {
        guard let value = setting.int else { return nil }
        self = value
    }

    var setting: SettingValue { .int(self) }
}

extension DateStyle: SettingChoice {
    init?(setting: SettingValue) {
        guard let value = setting.string.flatMap(DateStyle.init(rawValue:)) else { return nil }
        self = value
    }

    var setting: SettingValue { .string(rawValue) }
}

/// A setting's title, and beneath it what became of the phone's edit to it.
struct SettingTitle: View {
    let title: LocalizedStringResource
    let key: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            EditNote(key: key)
        }
    }
}

/// "Waiting for the Watch" while the phone's edit to a setting waits, and
/// "Changed on the Watch" once the watch dropped it for another value.
struct EditNote: View {
    @Environment(PhoneLink.self) private var link
    let key: String

    var body: some View {
        Group {
            if link.isWaiting(key) {
                Text("Waiting for the Watch")
            } else if link.isChangedOnWatch(key) {
                Text("Changed on the Watch")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
