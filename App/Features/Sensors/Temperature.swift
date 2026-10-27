import AppKit
import FanKit
import SwiftUI

/// The unit temperatures are shown in, chosen in Settings › General.
enum TemperatureUnit: String, CaseIterable {
    /// Follows System Settings › General › Language & Region. The default.
    case automatic
    case celsius
    case fahrenheit

    static let storageKey = "temperatureUnit"
}

enum Temperature {
    static func format(_ celsius: Double, unit: TemperatureUnit, fractionDigits: Int = 1) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(fractionDigits))
        switch unit {
        case .automatic:
            // `.general` converts to the person's preferred unit.
            return measurement.formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: number))
        case .celsius:
            return measurement.formatted(.measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: number
            ))
        case .fahrenheit:
            return measurement.converted(to: .fahrenheit)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: number))
        }
    }

    /// The unit to show and edit temperatures in.
    static func displayUnit(for unit: TemperatureUnit) -> UnitTemperature {
        switch unit {
        case .automatic: return systemUnitSymbol == "°F" ? .fahrenheit : .celsius
        case .celsius: return .celsius
        case .fahrenheit: return .fahrenheit
        }
    }

    static func convert(_ celsius: Double, to unit: UnitTemperature) -> Double {
        Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit).value
    }

    /// What `.automatic` resolves to right now, shown next to the option in Settings.
    static var systemUnitSymbol: String {
        let boiling = format(100, unit: .automatic, fractionDigits: 0)
        return boiling.contains("212") ? "°F" : "°C"
    }
}

// MARK: - Display

extension SensorGroup {
    /// SF Symbols has no GPU symbol; a cube reads as 3D graphics.
    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cube"
        case .memory: return "memorychip"
        case .disks: return "internaldrive"
        case .other: return "sensor"
        }
    }

    var displayName: String {
        switch self {
        case .cpu: return String(localized: "CPU")
        case .gpu: return String(localized: "GPU")
        case .memory: return String(localized: "Memory")
        case .disks: return String(localized: "Disk Drives")
        case .other: return String(localized: "Other Sensors")
        }
    }
}

extension SensorKind {
    var symbolName: String {
        switch self {
        case .efficiencyCore, .performanceCore, .gpuCluster, .memory: return group.symbolName
        case .airflowLeft, .airflowRight: return "wind"
        case .charger: return "powerplug"
        case .battery: return "battery.75percent"
        case .batteryCell: return "battery.50percent"
        case .batteryGasGauge: return "minus.plus.batteryblock"
        case .powerManager: return "bolt"
        case .ssd: return "internaldrive"
        case .wireless: return "wifi"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        }
    }
}

extension TemperatureSensor {
    var displayName: String {
        if let label { return label }
        let number = number ?? 1
        switch kind {
        case .efficiencyCore: return String(localized: "Efficiency Core \(number)")
        case .performanceCore: return String(localized: "Performance Core \(number)")
        case .gpuCluster: return String(localized: "GPU Cluster \(number)")
        case .memory: return String(localized: "Memory \(number)")
        case .airflowLeft: return String(localized: "Airflow Left")
        case .airflowRight: return String(localized: "Airflow Right")
        case .charger: return String(localized: "Charger")
        case .battery: return String(localized: "Battery")
        case .batteryCell: return String(localized: "Battery \(number)")
        case .batteryGasGauge: return String(localized: "Battery Gas Gauge")
        case .powerManager: return String(localized: "Power Manager Die Average")
        case .ssd: return String(localized: "SSD")
        case .wireless: return String(localized: "Wi-Fi")
        case .trackpad: return String(localized: "Trackpad")
        }
    }
}

// MARK: - Heat colors

extension Color {
    /// The label color shifted toward the system red by `severity` (0…1): normal text below a sensor's
    /// warm limit, full red at its critical limit. Resolved per appearance, so it reads in light and dark.
    ///
    /// The shift starts at 40 % red and eases out, so a reading that just crossed its warm limit is
    /// already clearly red rather than a muddy brown or pale pink.
    static func heat(_ severity: Double) -> Color {
        guard severity > 0 else { return .primary }
        guard severity < 1 else { return Color(nsColor: .systemRed) }
        let fraction = 0.4 + 0.6 * severity.squareRoot()
        return Color(nsColor: NSColor(name: nil) { appearance in
            var color = NSColor.labelColor
            appearance.performAsCurrentDrawingAppearance {
                let label = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
                let red = NSColor.systemRed.usingColorSpace(.sRGB) ?? .systemRed
                color = label.blended(withFraction: fraction, of: red) ?? red
            }
            return color
        })
    }
}

/// A temperature colored by how close it is to its sensor's limit. At the limit it also shows a warning
/// symbol, so the state isn't carried by color alone (HIG › Accessibility).
struct HeatText: View {
    let celsius: Double
    let limits: ThermalLimits?
    let text: String

    var body: some View {
        let severity = limits?.severity(at: celsius) ?? 0
        let isCritical = limits?.isCritical(celsius) ?? false
        HStack(spacing: 4) {
            if isCritical {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
                .monospacedDigit()
        }
        .foregroundStyle(Color.heat(severity))
        .animation(.default, value: severity)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCritical ? Text("High") : Text(""))
        .help(helpText(isCritical: isCritical, severity: severity))
    }

    private func helpText(isCritical: Bool, severity: Double) -> String {
        guard let limits else { return "" }
        let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: TemperatureUnit.storageKey) ?? "") ??
            .automatic
        let critical = Temperature.format(limits.criticalCelsius, unit: unit, fractionDigits: 0)
        if isCritical { return String(localized: "At or above \(critical), high for this sensor.") }
        if severity > 0 { return String(localized: "Warming up; high from \(critical).") }
        return ""
    }
}

extension HardwareSnapshot {
    /// How close the hottest sensor is to its own critical limit, 0…1. Drives the sidebar's dot.
    var maximumSeverity: Double {
        sensors.map { $0.kind.thermalLimits.severity(at: $0.celsius) }.max() ?? 0
    }

    var hasCriticalSensor: Bool {
        sensors.contains { $0.kind.thermalLimits.isCritical($0.celsius) }
    }
}
