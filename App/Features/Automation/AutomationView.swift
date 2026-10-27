import FanKit
import SwiftUI

/// Rules that switch profiles automatically. Checked top to bottom; the first that applies wins.
struct AutomationView: View {
    @Bindable var automation: AutomationController
    let profiles: ProfileStore

    var body: some View {
        Form {
            Section {
                Toggle("Switch profiles automatically", isOn: $automation.isEnabled)
                if automation.isEnabled {
                    LabeledContent("Now") {
                        if let rule = automation.matchedRule, let profile = profiles.profile(rule.profileID) {
                            Text("\(rule.condition.displayName) → \(profiles.displayName(of: profile))")
                        } else {
                            Text("No rule applies")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                if automation.rules.isEmpty {
                    Text("No rules yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(automation.rules.enumerated()), id: \.element.id) { index, rule in
                    RuleRow(
                        rule: rule,
                        isFirst: index == 0,
                        isLast: index == automation.rules.count - 1,
                        automation: automation,
                        profiles: profiles
                    )
                }
                Menu("Add Rule") {
                    Button("On Battery") { automation.add(.onBattery) }
                    Button("On Power Adapter") { automation.add(.onPowerAdapter) }
                    Button("When an App Is Open…") { automation.addAppRule() }
                }
                .fixedSize()
            } header: {
                Text("Rules")
            } footer: {
                Text(
                    "Rules are checked from top to bottom and the first one that applies is used. When none applies, the profile you chose yourself comes back."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .disabled(!automation.isEnabled)
        }
        .formStyle(.grouped)
        .navigationTitle("Profile Switching")
    }
}

private struct RuleRow: View {
    let rule: AutomationRule
    let isFirst: Bool
    let isLast: Bool
    let automation: AutomationController
    let profiles: ProfileStore

    var body: some View {
        LabeledContent {
            HStack {
                Picker("Profile", selection: profileBinding) {
                    ForEach(profiles.profiles) { profile in
                        Text(profiles.displayName(of: profile)).tag(profile.id)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Menu {
                    Toggle("Enabled", isOn: enabledBinding)
                    Divider()
                    Button("Move Up") { automation.move(rule.id, by: -1) }
                        .disabled(isFirst)
                    Button("Move Down") { automation.move(rule.id, by: 1) }
                        .disabled(isLast)
                    Divider()
                    Button("Delete Rule", role: .destructive) { automation.delete(rule.id) }
                } label: {
                    Label("Rule Actions", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Rule Actions")
            }
        } label: {
            Label(rule.condition.displayName, systemImage: rule.condition.symbolName)
                .foregroundStyle(rule.isEnabled ? .primary : .secondary)
        }
    }

    private var profileBinding: Binding<UUID> {
        Binding { rule.profileID } set: {
            var updated = rule
            updated.profileID = $0
            automation.update(updated)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding { rule.isEnabled } set: {
            var updated = rule
            updated.isEnabled = $0
            automation.update(updated)
        }
    }
}

extension AutomationRule.Condition {
    var displayName: String {
        switch self {
        case .onBattery: return String(localized: "On Battery")
        case .onPowerAdapter: return String(localized: "On Power Adapter")
        case .appRunning(_, let name): return String(localized: "While \(name) Is Open")
        }
    }

    var symbolName: String {
        switch self {
        case .onBattery: return "battery.50percent"
        case .onPowerAdapter: return "powerplug"
        case .appRunning: return "app"
        }
    }
}
