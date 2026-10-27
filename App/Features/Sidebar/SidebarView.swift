import FanKit
import SwiftUI

/// Two levels at most (HIG › Sidebars): Fans, Temperatures and Profiles, each item with a glanceable value.
struct SidebarView: View {
    let monitor: HardwareMonitor
    let profiles: ProfileStore
    let automation: AutomationController
    let alerts: AlertMonitor
    let thermalState: ThermalStateMonitor
    @Bindable var navigation: Navigation

    @AppStorage(TemperatureUnit.storageKey) private var unit = TemperatureUnit.automatic

    /// Where the Profiles section's header and rows are, in window coordinates.
    @State private var profileSectionFrames: [String: CGRect] = [:]
    /// The header or a profile row directly under the pointer.
    @State private var hoveredProfileParts: Set<String> = []
    /// The pointer is over the section's area, including the gaps between rows.
    @State private var isPointerInProfileArea = false

    private var showsProfileButtons: Bool {
        !hoveredProfileParts.isEmpty || isPointerInProfileArea
    }

    var body: some View {
        List(selection: $navigation.selection) {
            if let fans = monitor.snapshot?.fans, !fans.isEmpty {
                Section("Fans") {
                    ForEach(fans) { fan in
                        Label(fan.position.displayName, systemImage: "fan")
                            .badge(Text(fan.isStopped ? String(localized: "Stopped") : Fan
                                    .compactRPMText(fan.currentRPM)))
                            .tag(SidebarItem.fan(fan.id))
                    }
                }
            }

            Section("Sensors") {
                Label {
                    HStack(spacing: 6) {
                        Text("Temperatures")
                        HeatDot(snapshot: monitor.snapshot, thermalState: thermalState.state)
                    }
                } icon: {
                    Image(systemName: "thermometer.medium")
                }
                .badge(hottestText)
                .tag(SidebarItem.temperatures)
            }

            Section {
                ForEach(profiles.profiles) { profile in
                    ProfileSidebarRow(profile: profile, profiles: profiles, navigation: navigation)
                        .tag(SidebarItem.profile(profile.id))
                        .reportFrame(profile.id.uuidString)
                        .onHover { setHovered(profile.id.uuidString, $0) }
                }
            } header: {
                ProfilesHeader(profiles: profiles, navigation: navigation, showsButtons: showsProfileButtons)
                    .reportFrame("header")
                    .onHover { setHovered("header", $0) }
            }

            Section("Automation") {
                Label("Profile Switching", systemImage: "arrow.triangle.2.circlepath")
                    .badge(automation.isEnabled ? Text("On") : Text("Off"))
                    .tag(SidebarItem.automation)
                Label("Alerts", systemImage: "bell")
                    .badge(enabledAlertCount)
                    .tag(SidebarItem.alerts)
            }
        }
        .listStyle(.sidebar)
        .onPreferenceChange(FramePreferenceKey.self) { profileSectionFrames = $0 }
        // The gaps between rows receive no hover events, so the pointer is also tested against the section's
        // whole area. Both use window coordinates: List hosts each row separately, and a named coordinate
        // space resolved differently for the rows and for the pointer, shifting the area by the toolbar.
        .onContinuousHover(coordinateSpace: .global) { phase in
            let inside: Bool
            switch phase {
            case .active(let location): inside = profileSectionArea.contains(location)
            case .ended: inside = false
            }
            guard inside != isPointerInProfileArea else { return }
            withAnimation(.easeOut(duration: 0.15)) { isPointerInProfileArea = inside }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    }

    private func setHovered(_ part: String, _ hovering: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            if hovering {
                hoveredProfileParts.insert(part)
            } else {
                hoveredProfileParts.remove(part)
            }
        }
    }

    private var profileSectionArea: CGRect {
        let frames = profileSectionFrames.values
        guard let top = frames.map(\.minY).min(), let bottom = frames.map(\.maxY).max() else { return .null }
        return CGRect(x: -.greatestFiniteMagnitude / 2, y: top, width: .greatestFiniteMagnitude, height: bottom - top)
    }

    /// Hidden when zero, like Mail's unread counts.
    private var enabledAlertCount: Int {
        alerts.alerts.filter(\.isEnabled).count
    }

    private var hottestText: Text {
        guard let hottest = monitor.snapshot?.maximum(of: .cpu) else { return Text("") }
        return Text(Temperature.format(hottest, unit: unit, fractionDigits: 0))
    }
}

/// "Profiles" with New and Import buttons that appear while the pointer is over the section, as section
/// accessories do in Finder and Notes. They match the title's size, weight and color so they read as part of it.
private struct ProfilesHeader: View {
    let profiles: ProfileStore
    let navigation: Navigation
    let showsButtons: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("Profiles")
            Spacer(minLength: 16)
            Group {
                SectionHeaderButton(title: "New Profile", systemImage: "plus", help: "New Profile (⌘N)") {
                    navigation.selection = .profile(profiles.createProfile())
                }
                SectionHeaderButton(
                    title: "Import Profile…",
                    systemImage: "square.and.arrow.down",
                    help: "Import Profile…"
                ) {
                    navigation.isImportingProfile = true
                }
            }
            // Hidden visually only: VoiceOver and Full Keyboard Access still reach them.
            .opacity(showsButtons ? 1 : 0)
        }
        // Lines the last icon up with the rows' trailing check marks.
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .contextMenu { AddProfileCommands(profiles: profiles, navigation: navigation) }
    }
}

/// An icon-only button drawn like section header text. The title is its VoiceOver label; `help` its tooltip.
private struct SectionHeaderButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Header text color at rest, a step stronger under the pointer.
        .foregroundStyle(isHovering ? .secondary : .tertiary)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

/// New, Duplicate and Import: the Profiles header's context menu.
private struct AddProfileCommands: View {
    let profiles: ProfileStore
    let navigation: Navigation

    /// The profile selected in the sidebar, or else the active one.
    private var source: FanProfile? {
        profiles.profile(navigation.selectedProfileID ?? profiles.activeID)
    }

    var body: some View {
        Button("New Profile", systemImage: "plus") {
            navigation.selection = .profile(profiles.createProfile())
        }
        if let source {
            Button("Duplicate “\(profiles.displayName(of: source))”", systemImage: "plus.square.on.square") {
                if let copy = profiles.duplicate(source.id) { navigation.selection = .profile(copy) }
            }
        }
        Divider()
        Button("Import Profile…", systemImage: "square.and.arrow.down") {
            navigation.isImportingProfile = true
        }
    }
}

private struct ProfileSidebarRow: View {
    let profile: FanProfile
    let profiles: ProfileStore
    let navigation: Navigation

    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private var isActive: Bool { profiles.activeID == profile.id }
    private var isRenaming: Bool { navigation.renamingProfileID == profile.id }

    var body: some View {
        Group {
            if isRenaming {
                // Edited in place, like renaming in Finder: Return saves, Escape cancels.
                Label {
                    TextField("Name", text: $draftName)
                        .focused($isNameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { navigation.renamingProfileID = nil }
                        .onChange(of: isNameFocused) { _, focused in
                            if !focused { commitRename() }
                        }
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
                .onAppear {
                    draftName = profile.name
                    isNameFocused = true
                }
            } else {
                Label(
                    profiles.displayName(of: profile),
                    systemImage: profile.isEditable ? "slider.horizontal.3" : "lock"
                )
                // The active profile is marked with a symbol and, for VoiceOver, a word.
                .badge(isActive ? Text(Image(systemName: "checkmark")) : nil)
                .accessibilityValue(isActive ? Text("In Use") : Text(""))
            }
        }
        .contextMenu {
            Button("Use This Profile") { profiles.activate(profile.id) }
                .disabled(isActive)
            // Only the person's own profiles have a name they chose.
            if !profile.isBuiltIn {
                Button("Rename") { navigation.renamingProfileID = profile.id }
            }
            Button("Duplicate") {
                if let copy = profiles.duplicate(profile.id) { navigation.selection = .profile(copy) }
            }
            Button("Export…") { navigation.exportingProfileID = profile.id }
            Divider()
            Button("Delete…", role: .destructive) { navigation.profilePendingDeletion = profile.id }
                .disabled(profile.isBuiltIn)
        }
    }

    private func commitRename() {
        guard isRenaming else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { profiles.rename(profile.id, to: name) }
        navigation.renamingProfileID = nil
    }
}

extension Fan {
    /// The speed without its unit, for tight spaces such as the sidebar. The section title says "Fans".
    static func compactRPMText(_ rpm: Double) -> String {
        rpm.formatted(.number.precision(.fractionLength(0)))
    }
}

/// Collects the frames of views marked with `reportFrame`, keyed by name.
private struct FramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    /// Reports this view's frame in window coordinates, the same space `onContinuousHover(.global)` uses.
    func reportFrame(_ name: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: FramePreferenceKey.self, value: [name: geometry.frame(in: .global)])
        })
    }
}

/// A dot next to Temperatures once any sensor passes its warm limit, redder as the hottest sensor nears its
/// critical limit. VoiceOver hears "Warm" or "High" instead of a color.
private struct HeatDot: View {
    let snapshot: HardwareSnapshot?
    let thermalState: ProcessInfo.ThermalState

    /// The hotter of the sensors' own limits and macOS's thermal state.
    private var severity: Double {
        max(snapshot?.maximumSeverity ?? 0, thermalState.severity)
    }

    private var isHigh: Bool {
        snapshot?.hasCriticalSensor == true || thermalState == .serious || thermalState == .critical
    }

    var body: some View {
        if severity > 0 {
            Circle()
                .fill(Color.heat(isHigh ? 1 : severity))
                .frame(width: 7, height: 7)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(isHigh ? Text("High") : Text("Warm"))
                .help(isHigh
                    ? Text("A sensor is at or above its high limit, or macOS reports a high thermal state.")
                    : Text("A sensor is warming up."))
        }
    }
}
