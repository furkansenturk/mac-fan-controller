import Darwin
import SMCKit

/// Reads fans and temperatures from the SMC, plus the temperatures Apple Silicon only exposes through IOHID.
/// Read-only; writing happens in the privileged helper.
public actor HardwareReader {
    public nonisolated let chip: String

    private let smc: SMC
    private let hid = HIDTemperatures()
    private let fanCount: Int
    private let definitions: [SensorDefinition]

    public init() throws {
        let smc = try SMC()
        let chip = Self.chipName()

        self.smc = smc
        self.chip = chip
        fanCount = FanLimits.indices(count: smc.readDouble(.fanCount)).count
        // Keep only the keys this Mac actually exposes.
        definitions = SensorCatalog.definitions(forChip: chip).filter { smc.readDouble($0.key) != nil }
    }

    public func snapshot() -> HardwareSnapshot {
        HardwareSnapshot(fans: readFans(), sensors: readSensors())
    }

    private func readFans() -> [Fan] {
        (0..<fanCount).map { index in
            Fan(
                id: index,
                position: FanPosition(index: index, count: fanCount),
                currentRPM: smc.readDouble(.fanActual(index)) ?? 0,
                minimumRPM: smc.readDouble(.fanMinimum(index)) ?? 0,
                maximumRPM: smc.readDouble(.fanMaximum(index)) ?? 0,
                targetRPM: smc.readDouble(.fanTarget(index)) ?? 0,
                mode: smc.readDouble(.fanMode(index)) == 1 ? .manual : .automatic
            )
        }
    }

    private func readSensors() -> [TemperatureSensor] {
        let fromSMC = definitions.compactMap { definition -> TemperatureSensor? in
            // Sensors that are powered down report 0.
            guard let celsius = smc.readDouble(definition.key), celsius > 0 else { return nil }
            return TemperatureSensor(definition: definition, celsius: celsius)
        }
        return fromSMC + hid.read()
    }

    public static func chipName() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}
