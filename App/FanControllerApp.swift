import FanKit
import SwiftUI

@main
@MainActor
struct FanControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor: HardwareMonitor
    @State private var control: FanControl
    @State private var profiles: ProfileStore
    @State private var alerts: AlertMonitor
    @State private var automation: AutomationController
    @State private var navigation = Navigation()
    @State private var thermalState = ThermalStateMonitor()
    @AppStorage(AppPresence.showsMenuBarItemKey) private var showInMenuBar = true

    init() {
        let monitor = HardwareMonitor()
        _monitor = State(initialValue: monitor)
        let control = FanControl(monitor: monitor)
        _control = State(initialValue: control)
        let profiles = ProfileStore(monitor: monitor, control: control)
        _profiles = State(initialValue: profiles)
        _automation = State(initialValue: AutomationController(monitor: monitor, profiles: profiles))
        _alerts = State(initialValue: AlertMonitor(monitor: monitor))
    }

    var body: some Scene {
        Window("Fan Controller", id: WindowID.main) {
            ContentView(
                monitor: monitor,
                control: control,
                profiles: profiles,
                automation: automation,
                alerts: alerts,
                thermalState: thermalState,
                navigation: navigation
            )
        }
        .defaultSize(width: 760, height: 560)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
            }
            CommandGroup(after: .toolbar) {
                TemperatureViewCommands()
            }
            CommandMenu("Fans") {
                FanMenuItems(profiles: profiles, navigation: navigation)
            }
        }

        Window("About Fan Controller", id: WindowID.about) {
            AboutView(monitor: monitor)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarMenu(monitor: monitor, profiles: profiles, thermalState: thermalState)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(monitor: monitor, control: control)
        }
    }
}

enum WindowID {
    static let main = "main"
    static let about = "about"
}
