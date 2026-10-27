import FanKit
import Foundation
import Observation
import UserNotifications

/// Keeps the temperature alerts and posts a notification when one is crossed.
@MainActor
@Observable
final class AlertMonitor {
    private(set) var alerts: [TemperatureAlert]
    private(set) var notificationsAllowed: Bool?

    /// Alerts that fired and haven't cooled down yet.
    @ObservationIgnored private var firedAlerts: Set<UUID> = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var latestSnapshot: HardwareSnapshot?

    private static let storageKey = "temperatureAlerts"

    init(monitor: HardwareMonitor, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alerts = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([TemperatureAlert].self, from: $0) } ?? []
        monitor.addSnapshotHandler { [weak self] snapshot in
            self?.check(snapshot)
        }
        Task { await refreshAuthorization() }
    }

    // MARK: Editing

    /// Adds an alert for the hottest CPU core, 10 °C above its current reading (at least 80 °C).
    /// Asks for notification permission here, in context, rather than at launch (HIG › Privacy).
    func addAlert() {
        let current = latestSnapshot?.maximum(of: .cpu) ?? 70
        alerts.append(TemperatureAlert(source: .hottest(.cpu), thresholdCelsius: max(80, (current + 10).rounded())))
        save()
        Task { await requestAuthorization() }
    }

    func update(_ alert: TemperatureAlert) {
        guard let index = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[index] = alert
        // A changed alert starts over, so the new threshold can fire right away.
        firedAlerts.remove(alert.id)
        save()
    }

    func delete(_ id: UUID) {
        alerts.removeAll { $0.id == id }
        firedAlerts.remove(id)
        save()
    }

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: notificationsAllowed = true
        case .denied: notificationsAllowed = false
        default: notificationsAllowed = nil
        }
    }

    // MARK: Checking

    private func check(_ snapshot: HardwareSnapshot) {
        latestSnapshot = snapshot
        for alert in alerts where alert.isEnabled {
            guard let celsius = alert.source.celsius(in: snapshot) else { continue }
            switch alert.transition(celsius: celsius, armed: !firedAlerts.contains(alert.id)) {
            case .fire:
                firedAlerts.insert(alert.id)
                notify(alert, celsius: celsius, snapshot: snapshot)
            case .rearm:
                firedAlerts.remove(alert.id)
            case nil:
                break
            }
        }
    }

    private func notify(_ alert: TemperatureAlert, celsius: Double, snapshot: HardwareSnapshot) {
        let unit = TemperatureUnit(rawValue: defaults.string(forKey: TemperatureUnit.storageKey) ?? "") ?? .automatic
        let content = UNMutableNotificationContent()
        content
            .title =
            String(
                localized: "\(alert.source.displayName(in: snapshot)) is \(Temperature.format(celsius, unit: unit, fractionDigits: 0))"
            )
        content
            .body =
            String(
                localized: "Above your \(Temperature.format(alert.thresholdCelsius, unit: unit, fractionDigits: 0)) alert."
            )
        content.sound = .default
        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshAuthorization()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(alerts), forKey: Self.storageKey)
    }
}
