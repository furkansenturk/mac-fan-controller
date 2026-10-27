import Foundation

/// A temperature reading a rule or the menu bar can follow.
public enum TemperatureSource: Hashable, Sendable, Codable, RawRepresentable {
    case hottest(SensorGroup)
    case average(SensorGroup)
    /// A single sensor, by SMC key.
    case sensor(String)

    public init?(rawValue: String) {
        // Checked first: sensor keys can contain dots themselves ("sensor.hid.ssd").
        if rawValue.hasPrefix("sensor.") {
            self = .sensor(String(rawValue.dropFirst("sensor.".count)))
            return
        }
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let group = SensorGroup(rawValue: String(parts[0])) else { return nil }
        switch parts[1] {
        case "hottest": self = .hottest(group)
        case "average": self = .average(group)
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .hottest(let group): return "\(group.rawValue).hottest"
        case .average(let group): return "\(group.rawValue).average"
        case .sensor(let key): return "sensor.\(key)"
        }
    }

    public func celsius(in snapshot: HardwareSnapshot) -> Double? {
        switch self {
        case .hottest(let group): return snapshot.maximum(of: group)
        case .average(let group): return snapshot.average(of: group)
        case .sensor(let key): return snapshot.sensors.first { $0.id == key }?.celsius
        }
    }

    /// Stored as its raw value, e.g. "cpu.average", so saved profiles stay readable.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let source = TemperatureSource(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown source \(raw)"
            ))
        }
        self = source
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Raises the fan from its minimum to its maximum speed as a temperature climbs.
public struct SensorRule: Equatable, Sendable, Codable {
    public var source: TemperatureSource
    /// Further sources to watch; the rule follows whichever of all its sources is hottest,
    /// e.g. "CPU or GPU, whichever is hotter".
    public var extraSources: [TemperatureSource]
    /// At or below this temperature the fan runs at its minimum speed.
    public var lowerCelsius: Double
    /// At or above this temperature the fan runs at its maximum speed.
    public var upperCelsius: Double
    /// How far the temperature must fall before the fan slows down again, so it doesn't speed up and
    /// slow down over and over while the temperature hovers around one value.
    public var hysteresisCelsius: Double

    public init(
        source: TemperatureSource,
        extraSources: [TemperatureSource] = [],
        lowerCelsius: Double,
        upperCelsius: Double,
        hysteresisCelsius: Double = SensorRule.defaultHysteresis
    ) {
        self.source = source
        self.extraSources = extraSources
        self.lowerCelsius = lowerCelsius
        self.upperCelsius = upperCelsius
        self.hysteresisCelsius = hysteresisCelsius
    }

    public static let defaultHysteresis = 3.0

    public var sources: [TemperatureSource] { [source] + extraSources }

    /// The hottest reading among the rule's sources, or `nil` if none of them has a reading.
    public func celsius(in snapshot: HardwareSnapshot) -> Double? {
        sources.compactMap { $0.celsius(in: snapshot) }.max()
    }

    /// Profiles saved before extra sources and hysteresis existed decode with the defaults.
    private enum CodingKeys: String, CodingKey {
        case source, extraSources, lowerCelsius, upperCelsius, hysteresisCelsius
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(TemperatureSource.self, forKey: .source)
        extraSources = try container.decodeIfPresent([TemperatureSource].self, forKey: .extraSources) ?? []
        lowerCelsius = try container.decode(Double.self, forKey: .lowerCelsius)
        upperCelsius = try container.decode(Double.self, forKey: .upperCelsius)
        hysteresisCelsius = try container.decodeIfPresent(Double.self, forKey: .hysteresisCelsius) ?? Self
            .defaultHysteresis
    }

    /// Where `celsius` falls between the two temperatures, from 0 to 1.
    public func fraction(at celsius: Double) -> Double {
        guard upperCelsius > lowerCelsius else { return celsius >= upperCelsius ? 1 : 0 }
        return min(max((celsius - lowerCelsius) / (upperCelsius - lowerCelsius), 0), 1)
    }

    public static let `default` = SensorRule(source: .hottest(.cpu), lowerCelsius: 50, upperCelsius: 80)
}

/// How one fan is driven.
public enum FanRule: Equatable, Sendable, Codable {
    /// The SMC chooses the speed.
    case automatic
    /// A fixed point in the fan's range: 0 is its minimum speed, 1 its maximum.
    case constant(fraction: Double)
    case sensorBased(SensorRule)

    /// The speed this rule asks for right now, or `nil` when the SMC should decide. Always `nil` for a fan
    /// whose speed range couldn't be read (see `Fan.hasKnownRange`).
    ///
    /// `celsiusOverride` replaces the measured temperature of a sensor-based rule; the caller passes the
    /// hysteresis-adjusted value from `Hysteresis.effective`.
    public func targetRPM(for fan: Fan, in snapshot: HardwareSnapshot, celsiusOverride: Double? = nil) -> Double? {
        guard fan.hasKnownRange else { return nil }
        switch self {
        case .automatic:
            return nil
        case .constant(let fraction):
            return fan.rpm(at: fraction)
        case .sensorBased(let rule):
            // Without a reading, err on the side of cooling.
            guard let celsius = celsiusOverride ?? rule.celsius(in: snapshot) else { return fan.maximumRPM }
            return fan.rpm(at: rule.fraction(at: celsius))
        }
    }
}

/// A named set of fan rules. Fans without their own rule follow `defaultRule`.
public struct FanProfile: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var defaultRule: FanRule
    /// Rules per SMC fan index.
    public var rules: [Int: FanRule]

    public init(id: UUID = UUID(), name: String, defaultRule: FanRule = .automatic, rules: [Int: FanRule] = [:]) {
        self.id = id
        self.name = name
        self.defaultRule = defaultRule
        self.rules = rules
    }

    public func rule(for fan: Int) -> FanRule {
        rules[fan] ?? defaultRule
    }

    /// Ships with the app and can't be deleted: Automatic, Full Speed and Custom.
    public var isBuiltIn: Bool {
        Self.builtIn.contains { $0.id == id }
    }

    /// Whether the rules can change. Automatic and Full Speed are fixed; Custom is the one
    /// built-in profile meant to be edited, from the fan pages.
    public var isEditable: Bool {
        id != Self.automatic.id && id != Self.fullSpeed.id
    }

    /// Every fan automatic. The default profile.
    public static let automatic = FanProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000A0A0")!,
        name: "Automatic"
    )

    /// Every fan at its maximum speed.
    public static let fullSpeed = FanProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000F0F0")!,
        name: "Full Speed",
        defaultRule: .constant(fraction: 1)
    )

    /// The working profile: changing a fan from its own page switches here.
    /// Editable but never deleted, and the starting point for new profiles.
    public static let custom = FanProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000C0C0")!,
        name: "Custom"
    )

    public static let builtIn = [automatic, fullSpeed, custom]
}

public extension Fan {
    /// The speed at `fraction` of this fan's range.
    func rpm(at fraction: Double) -> Double {
        minimumRPM + (maximumRPM - minimumRPM) * min(max(fraction, 0), 1)
    }

    /// Where `rpm` sits in this fan's range, from 0 to 1.
    func fraction(of rpm: Double) -> Double {
        guard maximumRPM > minimumRPM else { return 0 }
        return min(max((rpm - minimumRPM) / (maximumRPM - minimumRPM), 0), 1)
    }
}

/// Keeps a fan from speeding up and slowing down over and over around one temperature.
///
/// Rising temperatures are followed immediately. Falling ones only once they are `band` degrees below the
/// temperature the fan last followed; until then the fan keeps its speed.
public enum Hysteresis {
    public static func effective(current: Double, previous: Double?, band: Double) -> Double {
        guard let previous, band > 0 else { return current }
        if current >= previous || current <= previous - band { return current }
        return previous
    }
}
