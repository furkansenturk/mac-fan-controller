import AppKit
import ServiceManagement
import SwiftUI

enum SettingsPane: String {
    case general
    case menuBar
    case fanControl

    /// Stored so the window reopens on the last pane (HIG › Settings) and menus can jump to a pane.
    static let storageKey = "settingsPane"
}

/// Opened from the app menu with ⌘, (HIG › Settings). The toolbar panes and window title come from TabView.
struct SettingsView: View {
    let monitor: HardwareMonitor
    let control: FanControl

    @AppStorage(SettingsPane.storageKey) private var pane = SettingsPane.general

    var body: some View {
        TabView(selection: $pane) {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsPane.general)

            MenuBarSettingsPane(monitor: monitor)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                .tag(SettingsPane.menuBar)

            FanControlSettingsPane(control: control)
                .tabItem { Label("Fan Control", systemImage: "fan") }
                .tag(SettingsPane.fanControl)
        }
        .frame(width: 460)
        .fixedSize()
    }
}

/// Opens Settings directly on the Fan Control pane, from fan error messages.
struct FanControlSettingsButton: View {
    var title: LocalizedStringKey

    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsPane.storageKey) private var pane = SettingsPane.general

    var body: some View {
        Button(title) {
            pane = .fanControl
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    @AppStorage(AppPresence.showsDockIconKey) private var showsDockIcon = true
    @AppStorage(AppPresence.showsMenuBarItemKey) private var showsMenuBarItem = true
    @State private var language = AppLanguage.current
    @AppStorage(TemperatureUnit.storageKey) private var temperatureUnit = TemperatureUnit.automatic
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Picker("Temperature unit", selection: $temperatureUnit) {
                    Text("Automatic (\(Temperature.systemUnitSymbol))").tag(TemperatureUnit.automatic)
                    Text("Celsius (°C)").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit (°F)").tag(TemperatureUnit.fahrenheit)
                }

                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: language) { _, newValue in
                    AppLanguage.set(newValue)
                }

                if language != AppLanguage.atLaunch {
                    LabeledContent {
                        Button("Restart Now") { AppLanguage.relaunch() }
                    } label: {
                        Text("Restart Fan Controller to use the new language.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Show icon in Dock", isOn: $showsDockIcon)
                    .onChange(of: showsDockIcon) { _, shows in
                        AppPresence.applyDockIcon(shows)
                    }
                    // One of the two must stay, or the app can't be reached.
                    .disabled(!showsMenuBarItem)

                Toggle("Open at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in
                        updateLoginItem(enabled)
                    }

                if let loginItemError {
                    Text(loginItemError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if !showsMenuBarItem {
                    Text("The Dock icon stays while the menu bar item is hidden, so Fan Controller remains reachable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if !showsDockIcon {
                    Text(
                        "Without a Dock icon, Fan Controller lives in the menu bar and its menus don’t appear at the top of the screen."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Fan Control

/// Everything about the privileged helper in one place: its state, its permission and how to repair it.
struct FanControlSettingsPane: View {
    let control: FanControl

    var body: some View {
        Form {
            Section {
                LabeledContent("Helper") {
                    StatusLabel(status: control.helperStatus.statusIndicator)
                }
                LabeledContent("Connection") {
                    HStack(spacing: 8) {
                        StatusLabel(status: control.connectionState.statusIndicator)
                        Button("Check Again") {
                            Task { await control.checkConnection() }
                        }
                        .disabled(control.helperStatus != .enabled || control.connectionState == .checking)
                    }
                }
            } footer: {
                Text(
                    "Fan Controller uses a small helper to change fan speeds, because only the system can write to the fan controller. Reading temperatures doesn’t need it."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Button("Open Login Items") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } label: {
                    Text("Permission")
                    Text("Allow or turn off the helper in System Settings.")
                }

                LabeledContent {
                    Button("Reinstall") {
                        Task { await control.reinstallHelper() }
                    }
                } label: {
                    Text("Reinstall helper")
                    Text("Fixes fan control after the app was rebuilt, updated or moved.")
                }

                LabeledContent {
                    Button("Remove", role: .destructive) {
                        Task { await control.removeHelper() }
                    }
                    .disabled(control.helperStatus == .notInstalled)
                } label: {
                    Text("Remove helper")
                    Text("Returns all fans to automatic and uninstalls the helper.")
                }
            } footer: {
                if let error = control.helperError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await control.checkConnection() }
        // The person may have changed the permission in System Settings meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await control.checkConnection() }
        }
    }
}

// MARK: - Status display

/// A symbol plus text, so state never relies on color alone (HIG › Accessibility).
struct StatusIndicator: Equatable {
    let text: String
    let symbol: String
    let color: Color
}

struct StatusLabel: View {
    let status: StatusIndicator

    var body: some View {
        Label {
            Text(status.text)
        } icon: {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
        }
        .foregroundStyle(.secondary)
    }
}

extension FanControl.HelperStatus {
    var statusIndicator: StatusIndicator {
        switch self {
        case .notInstalled:
            return StatusIndicator(text: String(localized: "Not installed"), symbol: "minus.circle", color: .secondary)
        case .requiresApproval:
            return StatusIndicator(
                text: String(localized: "Waiting for approval"),
                symbol: "exclamationmark.triangle.fill",
                color: .yellow
            )
        case .enabled:
            return StatusIndicator(text: String(localized: "On"), symbol: "checkmark.circle.fill", color: .green)
        }
    }
}

extension FanControl.ConnectionState {
    var statusIndicator: StatusIndicator {
        switch self {
        case .unknown:
            return StatusIndicator(text: String(localized: "Not checked"), symbol: "minus.circle", color: .secondary)
        case .checking:
            return StatusIndicator(text: String(localized: "Checking…"), symbol: "ellipsis.circle", color: .secondary)
        case .responding(let version):
            return StatusIndicator(
                text: String(localized: "Responding (build \(version))"),
                symbol: "checkmark.circle.fill",
                color: .green
            )
        case .notResponding:
            return StatusIndicator(text: String(localized: "Not responding"), symbol: "xmark.octagon.fill", color: .red)
        }
    }
}
