import FanKit
import SwiftUI

/// A fan's live state and its control. Changes made here go to the built-in Custom profile.
struct FanDetailView: View {
    let fan: Fan
    let snapshot: HardwareSnapshot
    let profiles: ProfileStore
    let control: FanControl
    let navigation: Navigation

    private var rule: FanRule { profiles.active.rule(for: fan.id) }

    var body: some View {
        Form {
            if control.helperStatus == .requiresApproval {
                HelperApprovalSection()
            }

            Section {
                FanSpeedRow(fan: fan)
            }

            Section {
                LabeledContent("Profile") {
                    Button(profiles.displayName(of: profiles.active)) {
                        navigation.selection = .profile(profiles.activeID)
                    }
                    .buttonStyle(.link)
                    .help("Show this profile")
                }
            }

            ProfileFanSection(
                title: String(localized: "Control"),
                fan: fan,
                rule: rule,
                snapshot: snapshot,
                isEditable: true,
                error: control.errors[fan.id]
            ) {
                note
            } commit: { rule in
                profiles.setRuleFromFanPage(rule, for: fan.id)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(fan.position.displayName)
    }

    /// Says where a change here goes, so switching to Custom is never a surprise.
    @ViewBuilder
    private var note: some View {
        if profiles.activeID == FanProfile.custom.id {
            HStack(spacing: 4) {
                Text("Changes are saved to the Custom profile.")
                    .foregroundStyle(.secondary)
                Button("Save as New Profile") {
                    navigation.selection = .profile(profiles.saveCustomAsNewProfile())
                }
                .buttonStyle(.link)
            }
        } else {
            Text(
                "Changing this switches to the Custom profile, starting from “\(profiles.displayName(of: profiles.active))”."
            )
            .foregroundStyle(.secondary)
        }
    }
}
