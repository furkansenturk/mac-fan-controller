import Foundation

/// "When this is true, use that profile."
public struct AutomationRule: Identifiable, Equatable, Sendable, Codable {
    public enum Condition: Equatable, Sendable, Codable {
        case onBattery
        case onPowerAdapter
        /// An app is open, identified by bundle ID; `name` is for display.
        case appRunning(bundleID: String, name: String)
    }

    public let id: UUID
    public var condition: Condition
    public var profileID: UUID
    public var isEnabled: Bool

    public init(id: UUID = UUID(), condition: Condition, profileID: UUID, isEnabled: Bool = true) {
        self.id = id
        self.condition = condition
        self.profileID = profileID
        self.isEnabled = isEnabled
    }
}

/// The state automation rules look at, gathered by the app.
public struct AutomationContext: Equatable, Sendable {
    public var isOnBattery: Bool
    public var runningBundleIDs: Set<String>

    public init(isOnBattery: Bool, runningBundleIDs: Set<String>) {
        self.isOnBattery = isOnBattery
        self.runningBundleIDs = runningBundleIDs
    }
}

public enum Automation {
    /// The first enabled rule that applies and whose profile still exists. Rules are checked in order.
    public static func matchingRule(
        in rules: [AutomationRule],
        context: AutomationContext,
        existingProfiles: Set<UUID>
    ) -> AutomationRule? {
        rules.first { rule in
            guard rule.isEnabled, existingProfiles.contains(rule.profileID) else { return false }
            switch rule.condition {
            case .onBattery: return context.isOnBattery
            case .onPowerAdapter: return !context.isOnBattery
            case .appRunning(let bundleID, _): return context.runningBundleIDs.contains(bundleID)
            }
        }
    }
}
