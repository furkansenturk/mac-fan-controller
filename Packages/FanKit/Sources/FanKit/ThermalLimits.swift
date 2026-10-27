/// When a reading starts to count as warm, and when it is a concern, per kind of sensor.
///
/// Apple doesn't publish limits per sensor. These are reasoned defaults from known hardware behaviour:
/// Apple Silicon throttles around 100–105 °C, NVMe SSDs slow down around 70–80 °C, Apple advises against
/// batteries running above 35 °C, and surfaces people touch become uncomfortable from about 43 °C.
public struct ThermalLimits: Equatable, Sendable {
    /// From here the reading starts to be shown in a warmer color.
    public let warmCelsius: Double
    /// At and above this the reading is shown as a concern.
    public let criticalCelsius: Double

    public init(warmCelsius: Double, criticalCelsius: Double) {
        self.warmCelsius = warmCelsius
        self.criticalCelsius = criticalCelsius
    }

    /// 0 at or below `warmCelsius`, 1 at or above `criticalCelsius`, linear in between.
    public func severity(at celsius: Double) -> Double {
        guard criticalCelsius > warmCelsius else { return celsius >= criticalCelsius ? 1 : 0 }
        return min(max((celsius - warmCelsius) / (criticalCelsius - warmCelsius), 0), 1)
    }

    public func isCritical(_ celsius: Double) -> Bool {
        celsius >= criticalCelsius
    }
}

public extension SensorKind {
    var thermalLimits: ThermalLimits {
        switch self {
        case .efficiencyCore, .performanceCore, .gpuCluster:
            // Apple Silicon throttles at about 100–105 °C; sustained 95 °C is close to that.
            return ThermalLimits(warmCelsius: 70, criticalCelsius: 95)
        case .memory:
            return ThermalLimits(warmCelsius: 65, criticalCelsius: 90)
        case .ssd:
            // NVMe drives typically throttle at 70–80 °C.
            return ThermalLimits(warmCelsius: 50, criticalCelsius: 70)
        case .battery, .batteryCell, .batteryGasGauge:
            // Above 35 °C shortens battery life; above 45 °C is harmful.
            return ThermalLimits(warmCelsius: 35, criticalCelsius: 45)
        case .charger:
            return ThermalLimits(warmCelsius: 50, criticalCelsius: 70)
        case .powerManager:
            return ThermalLimits(warmCelsius: 60, criticalCelsius: 85)
        case .wireless:
            return ThermalLimits(warmCelsius: 55, criticalCelsius: 75)
        case .airflowLeft, .airflowRight:
            return ThermalLimits(warmCelsius: 50, criticalCelsius: 65)
        case .trackpad:
            // A surface under the hands: uncomfortable from about 43 °C.
            return ThermalLimits(warmCelsius: 38, criticalCelsius: 45)
        }
    }
}

public extension SensorGroup {
    /// Limits for a group's summary (average or hottest), taken from its typical sensor.
    var thermalLimits: ThermalLimits? {
        switch self {
        case .cpu: return SensorKind.performanceCore.thermalLimits
        case .gpu: return SensorKind.gpuCluster.thermalLimits
        case .memory: return SensorKind.memory.thermalLimits
        case .disks: return SensorKind.ssd.thermalLimits
        case .other: return nil
        }
    }
}
