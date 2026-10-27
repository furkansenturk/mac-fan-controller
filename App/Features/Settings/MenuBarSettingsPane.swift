import FanKit
import SwiftUI

/// Everything about the menu bar item: whether it appears and what it shows.
struct MenuBarSettingsPane: View {
    let monitor: HardwareMonitor

    @AppStorage(AppPresence.showsMenuBarItemKey) private var showInMenuBar = true
    @AppStorage(AppPresence.showsDockIconKey) private var showsDockIcon = true
    @AppStorage(MenuBarPreferences.showsIconKey) private var showsIcon = true
    @AppStorage(MenuBarPreferences.temperatureSourceKey) private var temperature = MenuBarTemperature(.hottest(.cpu))
    @AppStorage(MenuBarPreferences.fansKey) private var fans = MenuBarFanSelection()

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                    // One of the two must stay, or the app can't be reached.
                    .disabled(!showsDockIcon)
            } footer: {
                if !showsDockIcon {
                    Text("The menu bar item stays while the Dock icon is hidden, so Fan Controller remains reachable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Icon", isOn: $showsIcon)

                Picker("Temperature", selection: $temperature) {
                    Text("None").tag(MenuBarTemperature(nil))
                    TemperatureSourceOptions(snapshot: monitor.snapshot) { MenuBarTemperature($0) }
                }

                ForEach(monitor.snapshot?.fans ?? []) { fan in
                    Toggle("\(fan.position.displayName) speed", isOn: binding(for: fan))
                }
            } header: {
                Text("Show")
            } footer: {
                Text("If nothing is selected, the icon is shown so Fan Controller stays reachable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .disabled(!showInMenuBar)
        }
        .formStyle(.grouped)
    }

    private func binding(for fan: Fan) -> Binding<Bool> {
        Binding {
            fans.fanIDs.contains(fan.id)
        } set: { isOn in
            if isOn {
                fans.fanIDs.insert(fan.id)
            } else {
                fans.fanIDs.remove(fan.id)
            }
        }
    }
}
