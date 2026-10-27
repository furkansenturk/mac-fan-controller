import SMCKit

/// One fan as reported by the SMC.
public struct Fan: Identifiable, Equatable, Sendable {
    /// The SMC fan index (`F<id>Ac`, `F<id>Mn`, …).
    public let id: Int
    public let position: FanPosition
    public var currentRPM: Double
    public var minimumRPM: Double
    public var maximumRPM: Double
    /// The speed the SMC aims for in manual mode.
    public var targetRPM: Double
    public var mode: FanMode

    public init(
        id: Int,
        position: FanPosition,
        currentRPM: Double,
        minimumRPM: Double,
        maximumRPM: Double,
        targetRPM: Double,
        mode: FanMode
    ) {
        self.id = id
        self.position = position
        self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM
        self.mode = mode
    }

    /// Where the current speed sits between the minimum and maximum, from 0 to 1.
    public var load: Double {
        guard maximumRPM > minimumRPM else { return 0 }
        return min(max((currentRPM - minimumRPM) / (maximumRPM - minimumRPM), 0), 1)
    }

    /// Whether the SMC reported a usable speed range (see `FanLimits.isUsableRange`). Without one the fan
    /// is left to the SMC.
    public var hasKnownRange: Bool {
        FanLimits.isUsableRange(minimum: minimumRPM, maximum: maximumRPM)
    }

    /// `rpm` limited to the speeds this fan supports.
    public func clamped(_ rpm: Double) -> Double {
        min(max(rpm, minimumRPM), maximumRPM)
    }
}

/// The SMC does not name fans on Apple Silicon. Like other fan utilities we infer the position:
/// on two-fan MacBook Pros fan 0 sits on the left.
public enum FanPosition: Equatable, Sendable {
    case only
    case left
    case right
    case numbered(Int)

    public init(index: Int, count: Int) {
        switch (count, index) {
        case (1, _): self = .only
        case (2, 0): self = .left
        case (2, 1): self = .right
        default: self = .numbered(index + 1)
        }
    }
}

public enum FanMode: Equatable, Sendable {
    /// The SMC chooses the speed.
    case automatic
    /// The speed follows `F<n>Tg`, set by the privileged helper.
    case manual
}

/// A temperature reading with a known meaning, from the SMC or from an IOHID sensor.
public struct TemperatureSensor: Identifiable, Equatable, Sendable {
    /// The SMC key such as `Tp01`, or `hid.<name>` for HID sensors. Stable, so rules can refer to it.
    public let id: String
    public let kind: SensorKind
    /// Distinguishes cores and clusters (1-based).
    public let number: Int?
    /// A name the hardware reports, such as a disk's model ("APPLE SSD AP0512R"). Shown instead of the kind's name.
    public let label: String?
    public var celsius: Double

    public init(id: String, kind: SensorKind, number: Int? = nil, label: String? = nil, celsius: Double) {
        self.id = id
        self.kind = kind
        self.number = number
        self.label = label
        self.celsius = celsius
    }

    public init(definition: SensorDefinition, celsius: Double) {
        self.init(id: definition.key.name, kind: definition.kind, number: definition.number, celsius: celsius)
    }
}

/// Everything the UI shows, read in one pass.
public struct HardwareSnapshot: Equatable, Sendable {
    public var fans: [Fan]
    public var sensors: [TemperatureSensor]

    public init(fans: [Fan], sensors: [TemperatureSensor]) {
        self.fans = fans
        self.sensors = sensors
    }

    public func sensors(in group: SensorGroup) -> [TemperatureSensor] {
        sensors.filter { $0.kind.group == group }
    }

    /// Mean temperature of a group, e.g. "CPU Core Average". `nil` when the group is empty.
    public func average(of group: SensorGroup) -> Double? {
        let values = sensors(in: group).map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// The hottest reading of a group, used for the menu bar summary.
    public func maximum(of group: SensorGroup) -> Double? {
        sensors(in: group).map(\.celsius).max()
    }
}
