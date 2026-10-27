import AppKit
import FanKit
import SwiftUI

/// Temperature alerts: a sensor and a limit each, delivered as notifications.
struct AlertsView: View {
    let alerts: AlertMonitor
    let monitor: HardwareMonitor

    @AppStorage(TemperatureUnit.storageKey) private var unit = TemperatureUnit.automatic

    /// The re-arm distance in the person's unit; a difference, so 5 °C is 9 °F.
    private var rearmText: String {
        let displayUnit = Temperature.displayUnit(for: unit)
        let factor = displayUnit == .fahrenheit ? 1.8 : 1
        return "\(Int((TemperatureAlert.rearmBelowCelsius * factor).rounded())) \(displayUnit.symbol)"
    }

    var body: some View {
        Form {
            if alerts.notificationsAllowed == false {
                Section {
                    LabeledContent {
                        Button("Open System Settings") {
                            NSWorkspace.shared
                                .open(
                                    URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
                                )
                        }
                    } label: {
                        Label {
                            Text("Notifications are off")
                            Text("Allow notifications for Fan Controller to receive alerts.")
                        } icon: {
                            Image(systemName: "bell.slash")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ForEach(alerts.alerts) { alert in
                AlertSection(alert: alert, snapshot: monitor.snapshot, alerts: alerts)
            }

            Section {
                Button("Add Alert") { alerts.addAlert() }
            } footer: {
                Text(
                    "You’re notified once when a temperature goes above its limit, and again only after it has cooled \(rearmText) below it."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Alerts")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await alerts.refreshAuthorization() }
        }
    }
}

private struct AlertSection: View {
    let alert: TemperatureAlert
    let snapshot: HardwareSnapshot?
    let alerts: AlertMonitor

    var body: some View {
        Section {
            Toggle("Alert", isOn: binding(\.isEnabled))
            Picker("Sensor", selection: binding(\.source)) {
                TemperatureSourceOptions(snapshot: snapshot) { $0 }
            }
            TemperatureField(title: "Notify above", celsius: binding(\.thresholdCelsius))
            Button("Delete Alert", role: .destructive) { alerts.delete(alert.id) }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TemperatureAlert, Value>) -> Binding<Value> {
        Binding {
            alert[keyPath: keyPath]
        } set: {
            var updated = alert
            updated[keyPath: keyPath] = $0
            alerts.update(updated)
        }
    }
}
