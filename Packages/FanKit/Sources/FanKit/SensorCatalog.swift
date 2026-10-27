import SMCKit

/// What a temperature key measures. Display names are localized by the app.
public enum SensorKind: String, CaseIterable, Sendable {
    case efficiencyCore
    case performanceCore
    case gpuCluster
    case memory
    case airflowLeft
    case airflowRight
    case charger
    case battery
    /// One of the battery's cell sensors (`TB1T`, `TB2T`); `battery` (`TB0T`) is the hottest of them.
    case batteryCell
    /// The battery's fuel gauge chip (HID "gas gauge battery").
    case batteryGasGauge
    /// Average of the power management IC's die sensors (HID "PMU tdie…").
    case powerManager
    /// The internal SSD (HID "NAND CH0 temp"), named after the drive's model.
    case ssd
    case wireless
    case trackpad

    public var group: SensorGroup {
        switch self {
        case .efficiencyCore, .performanceCore: return .cpu
        case .gpuCluster: return .gpu
        case .memory: return .memory
        case .ssd: return .disks
        case .airflowLeft, .airflowRight, .charger, .battery, .batteryCell, .batteryGasGauge, .powerManager,
             .wireless, .trackpad:
            return .other
        }
    }
}

public enum SensorGroup: String, CaseIterable, Sendable {
    case cpu
    case gpu
    case memory
    case disks
    case other

    /// Whether an average across the group means something. A single disk or a mix of unrelated
    /// sensors has no useful average.
    public var hasAverage: Bool {
        switch self {
        case .cpu, .gpu, .memory: return true
        case .disks, .other: return false
        }
    }
}

/// Maps an SMC key to its meaning. `number` distinguishes cores and clusters (1-based).
public struct SensorDefinition: Equatable, Sendable {
    public let key: SMCKey
    public let kind: SensorKind
    public let number: Int?

    public init(_ key: SMCKey, _ kind: SensorKind, _ number: Int? = nil) {
        self.key = key
        self.kind = kind
        self.number = number
    }
}

/// Known temperature keys per chip.
///
/// The same key can mean different things on different chips (`Tp09` is an efficiency core on
/// M1 Pro but a performance core on M2), so definitions are chosen by the chip name.
/// To add a Mac, run `Scripts/dump-sensors.sh` and see docs/smc-keys.md.
///
/// Apple doesn't document SMC keys. Names come from the open-source Stats app (Modules/Sensors/values.swift)
/// and the Asahi Linux SMC notes, and every key listed here was confirmed to exist on real hardware.
public enum SensorCatalog {
    public static func definitions(forChip chip: String) -> [SensorDefinition] {
        let chipSpecific: [SensorDefinition]
        switch chip {
        case "Apple M1 Pro", "Apple M1 Max":
            chipSpecific = m1ProMax
        default:
            chipSpecific = []
        }
        return chipSpecific + common
    }

    /// Verified on MacBookPro18,3 (M1 Pro).
    static let m1ProMax: [SensorDefinition] = [
        .init("Tp09", .efficiencyCore, 1),
        .init("Tp0T", .efficiencyCore, 2),
        .init("Tp01", .performanceCore, 1),
        .init("Tp05", .performanceCore, 2),
        .init("Tp0D", .performanceCore, 3),
        .init("Tp0H", .performanceCore, 4),
        .init("Tp0L", .performanceCore, 5),
        .init("Tp0P", .performanceCore, 6),
        .init("Tp0X", .performanceCore, 7),
        .init("Tp0b", .performanceCore, 8),
        .init("Tg05", .gpuCluster, 1),
        .init("Tg0D", .gpuCluster, 2),
        .init("Tg0L", .gpuCluster, 3),
        .init("Tg0T", .gpuCluster, 4),
        // Stats lists these four for the whole M1 generation; MacBookPro18,3 has the first two.
        .init("Tm02", .memory, 1),
        .init("Tm06", .memory, 2),
        .init("Tm08", .memory, 3),
        .init("Tm09", .memory, 4),
    ]

    /// Keys that keep their meaning across Apple Silicon Macs. Missing keys are skipped at runtime.
    static let common: [SensorDefinition] = [
        .init("TaLP", .airflowLeft),
        .init("TaRF", .airflowRight),
        .init("TCHP", .charger),
        .init("TB0T", .battery),
        .init("TB1T", .batteryCell, 1),
        .init("TB2T", .batteryCell, 2),
        .init("TW0P", .wireless),
        .init("Ts0P", .trackpad),
    ]
}
