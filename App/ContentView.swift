import AppKit
import FanKit
import ServiceManagement
import SwiftUI

/// The main window: a sidebar of fans, temperatures and profiles, and a detail view for the selection.
struct ContentView: View {
    let monitor: HardwareMonitor
    let control: FanControl
    let profiles: ProfileStore
    let automation: AutomationController
    let alerts: AlertMonitor
    let thermalState: ThermalStateMonitor
    @Bindable var navigation: Navigation

    var body: some View {
        NavigationSplitView {
            SidebarView(
                monitor: monitor,
                profiles: profiles,
                automation: automation,
                alerts: alerts,
                thermalState: thermalState,
                navigation: navigation
            )
        } detail: {
            detail
        }
        .frame(minWidth: 680, minHeight: 440)
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding {
                navigation.profilePendingDeletion != nil
            } set: { presented in
                if !presented { navigation.profilePendingDeletion = nil }
            },
            presenting: navigation.profilePendingDeletion
        ) { id in
            Button("Delete", role: .destructive) { delete(id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("If this profile is in use, the fans return to Automatic. This can’t be undone.")
        }
        .fileExporter(
            isPresented: Binding {
                navigation.exportingProfileID != nil
            } set: { presented in
                if !presented { navigation.exportingProfileID = nil }
            },
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportDocument.map { profiles.displayName(of: $0.profile) }
        ) { _ in
            navigation.exportingProfileID = nil
        }
        .fileImporter(isPresented: $navigation.isImportingProfile, allowedContentTypes: [.json]) { result in
            importProfile(from: result)
        }
        .alert(
            "Can’t Import Profile",
            isPresented: Binding {
                navigation.importError != nil
            } set: { presented in
                if !presented { navigation.importError = nil }
            }
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(navigation.importError ?? "")
        }
        // The person may have approved the helper in System Settings while we were in the background.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            control.refreshStatus()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch monitor.state {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Can’t Read Sensors", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .ready(let snapshot):
            switch navigation.selection {
            case .fan(let id):
                if let fan = snapshot.fans.first(where: { $0.id == id }) {
                    FanDetailView(
                        fan: fan,
                        snapshot: snapshot,
                        profiles: profiles,
                        control: control,
                        navigation: navigation
                    )
                } else {
                    ContentUnavailableView("This Mac doesn’t have fans.", systemImage: "fan")
                }
            case .temperatures:
                TemperaturesView(snapshot: snapshot, thermalState: thermalState.state)
            case .profile(let id):
                if let profile = profiles.profile(id) {
                    ProfileDetailView(
                        profile: profile,
                        snapshot: snapshot,
                        profiles: profiles,
                        control: control,
                        navigation: navigation
                    )
                } else {
                    ContentUnavailableView("Select an Item", systemImage: "sidebar.left")
                }
            case .automation:
                AutomationView(automation: automation, profiles: profiles)
            case .alerts:
                AlertsView(alerts: alerts, monitor: monitor)
            case nil:
                ContentUnavailableView("Select an Item", systemImage: "sidebar.left")
            }
        }
    }

    private var deleteTitle: String {
        guard let id = navigation.profilePendingDeletion, let profile = profiles.profile(id) else { return "" }
        return String(localized: "Delete “\(profiles.displayName(of: profile))”?")
    }

    private var exportDocument: ProfileFile? {
        navigation.exportingProfileID.flatMap(profiles.profile).map(ProfileFile.init(profile:))
    }

    private func importProfile(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let data = try Data(contentsOf: url)
            navigation.selection = .profile(profiles.importProfile(try ProfileExport.profile(from: data)))
        } catch let error as ProfileExport.ImportError {
            navigation.importError = error.message
        } catch {
            navigation.importError = error.localizedDescription
        }
    }

    private func delete(_ id: UUID) {
        profiles.delete(id)
        if navigation.selection == .profile(id) {
            navigation.selection = .profile(profiles.activeID)
        }
    }
}

/// Shown in place, not as an alert: the person can keep reading sensors without approving.
struct HelperApprovalSection: View {
    var body: some View {
        Section {
            LabeledContent {
                Button("Open System Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } label: {
                Label {
                    Text("Allow fan control")
                    Text("Turn on Fan Controller in Login Items so it can change fan speeds.")
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
