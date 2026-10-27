import FanKit
import SwiftUI

/// Edits one profile: its name and a rule per fan. Built-in profiles are shown read-only with a Duplicate button.
struct ProfileDetailView: View {
    let profile: FanProfile
    let snapshot: HardwareSnapshot
    let profiles: ProfileStore
    let control: FanControl
    let navigation: Navigation

    private var isActive: Bool { profiles.activeID == profile.id }

    var body: some View {
        Form {
            if isActive, control.helperStatus == .requiresApproval {
                HelperApprovalSection()
            }

            Section {
                if profile.isBuiltIn {
                    LabeledContent("Name", value: profiles.displayName(of: profile))
                } else {
                    TextField("Name", text: nameBinding, prompt: Text("Untitled Profile"))
                }

                LabeledContent {
                    if isActive {
                        Label("In Use", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Use This Profile") { profiles.activate(profile.id) }
                            .buttonStyle(.borderedProminent)
                    }
                } label: {
                    Text("Status")
                }
            } footer: {
                // Links are not tinted secondary so they read as links.
                if profile.id == FanProfile.custom.id {
                    HStack(spacing: 4) {
                        Text("Changes you make on a fan’s page are saved here.")
                            .foregroundStyle(.secondary)
                        Button("Save as New Profile") {
                            navigation.selection = .profile(profiles.saveCustomAsNewProfile())
                        }
                        .buttonStyle(.link)
                    }
                    .font(.callout)
                } else if !profile.isEditable {
                    HStack(spacing: 4) {
                        Text("This profile can’t be changed.")
                            .foregroundStyle(.secondary)
                        Button("Duplicate to Customize") {
                            if let copy = profiles.duplicate(profile.id) { navigation.selection = .profile(copy) }
                        }
                        .buttonStyle(.link)
                    }
                    .font(.callout)
                }
            }

            ForEach(snapshot.fans) { fan in
                ProfileFanSection(
                    title: fan.position.displayName,
                    fan: fan,
                    rule: profile.rule(for: fan.id),
                    snapshot: snapshot,
                    isEditable: profile.isEditable,
                    error: isActive ? control.errors[fan.id] : nil
                ) {
                    EmptyView()
                } commit: { rule in
                    profiles.setRule(rule, for: fan.id, in: profile.id)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(profiles.displayName(of: profile))
    }

    private var nameBinding: Binding<String> {
        Binding { profile.name } set: { profiles.rename(profile.id, to: $0) }
    }
}

/// Control › Automatic | Manual | Custom for one fan in one profile. Used by profile pages and fan pages.
struct ProfileFanSection<Note: View>: View {
    let title: String
    let fan: Fan
    let rule: FanRule
    let snapshot: HardwareSnapshot
    let isEditable: Bool
    let error: String?
    @ViewBuilder var note: Note
    let commit: (FanRule) -> Void

    enum ControlKind: Hashable {
        case automatic
        case manual
        case custom
    }

    var body: some View {
        Section {
            Picker("Control", selection: controlBinding) {
                Text("Automatic").tag(ControlKind.automatic)
                Text("Manual").tag(ControlKind.manual)
                Text("Custom").tag(ControlKind.custom)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            switch rule {
            case .automatic:
                EmptyView()
            case .constant(let fraction):
                ConstantSpeedRow(fan: fan, fraction: fraction) { commit(.constant(fraction: $0)) }
            case .sensorBased(let sensorRule):
                FanCurveChart(
                    fan: fan,
                    rule: sensorRule,
                    snapshot: snapshot,
                    onChange: isEditable ? { commit(.sensorBased($0)) } : nil
                )
                SensorRuleRows(fan: fan, snapshot: snapshot, sensorRule: sensorRule) { commit(.sensorBased($0)) }
            }
        } header: {
            Text(title)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                    FanControlSettingsButton(title: "Open Fan Control Settings")
                        .buttonStyle(.link)
                }
                note
            }
            .font(.callout)
        }
        .disabled(!isEditable)
    }

    private var controlBinding: Binding<ControlKind> {
        Binding {
            switch rule {
            case .automatic: return .automatic
            case .constant: return .manual
            case .sensorBased: return .custom
            }
        } set: { kind in
            switch (kind, rule) {
            case (.automatic, _):
                commit(.automatic)
            case (.manual, .constant), (.custom, .sensorBased):
                break
            case (.manual, _):
                // Start at the current speed so choosing Manual doesn't change anything audible.
                commit(.constant(fraction: fan.fraction(of: fan.currentRPM)))
            case (.custom, _):
                commit(.sensorBased(.default))
            }
        }
    }
}
