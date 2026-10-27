import AppKit
import FanKit
import IOKit.ps
import Observation

/// Switches profiles by itself: on battery, on the power adapter, or while a given app is open.
///
/// Acts only when the matching rule changes, so a profile the person picks by hand stays until the
/// situation changes (for example the power cable is plugged in). When no rule applies anymore,
/// the profile that was active before automation stepped in comes back.
@MainActor
@Observable
final class AutomationController {
    private(set) var rules: [AutomationRule]
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.enabled)
            if !isEnabled { stepBack() }
        }
    }

    /// The rule in effect, shown in Settings.
    private(set) var matchedRule: AutomationRule?

    @ObservationIgnored private let profiles: ProfileStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var profileBeforeAutomation: UUID?

    private enum Key {
        static let rules = "automationRules"
        static let enabled = "automationEnabled"
    }

    init(monitor: HardwareMonitor, profiles: ProfileStore, defaults: UserDefaults = .standard) {
        self.profiles = profiles
        self.defaults = defaults
        rules = defaults.data(forKey: Key.rules)
            .flatMap { try? JSONDecoder().decode([AutomationRule].self, from: $0) } ?? []
        isEnabled = defaults.bool(forKey: Key.enabled)
        monitor.addSnapshotHandler { [weak self] _ in
            self?.evaluate()
        }
    }

    // MARK: Editing

    func add(_ condition: AutomationRule.Condition) {
        rules.append(AutomationRule(condition: condition, profileID: profiles.activeID))
        save()
    }

    func update(_ rule: AutomationRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        save()
    }

    func delete(_ id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    func move(_ id: UUID, by offset: Int) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard rules.indices.contains(target) else { return }
        rules.swapAt(index, target)
        save()
    }

    /// Lets the person pick an app in /Applications for an "app is open" rule.
    func addAppRule() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier
        else {
            return
        }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        add(.appRunning(bundleID: bundleID, name: name))
    }

    // MARK: Evaluating

    private func evaluate() {
        guard isEnabled else { return }
        let match = Automation.matchingRule(
            in: rules,
            context: currentContext(),
            existingProfiles: Set(profiles.profiles.map(\.id))
        )
        guard match?.id != matchedRule?.id || match?.profileID != matchedRule?.profileID else { return }

        if let match {
            if matchedRule == nil { profileBeforeAutomation = profiles.activeID }
            profiles.activate(match.profileID)
        } else {
            stepBack()
        }
        matchedRule = match
    }

    /// Returns to the profile that was active before a rule applied.
    private func stepBack() {
        if matchedRule != nil, let previous = profileBeforeAutomation {
            profiles.activate(previous)
        }
        profileBeforeAutomation = nil
        matchedRule = nil
    }

    private func currentContext() -> AutomationContext {
        AutomationContext(
            isOnBattery: Self.isOnBattery(),
            runningBundleIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        )
    }

    private static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == "Battery Power" // kIOPMBatteryPowerKey
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(rules), forKey: Key.rules)
    }
}
