import CIOHID
import Foundation

/// Temperatures Apple Silicon exposes as IOHID sensors rather than SMC keys: the SSD, the battery's
/// fuel gauge and the power management IC. Their product names are stable across Apple Silicon Macs.
///
/// Uses the IOHIDEventSystemClient API (declared in CIOHID), which is not public but is what sensor
/// utilities on Apple Silicon rely on. If any call fails, the reader reports no sensors instead of failing.
public final class HIDTemperatures {
    private let client: IOHIDEventSystemClient?
    /// Read once: the drive doesn't change while the app runs.
    private let diskName = InternalDisk.productName()

    public init() {
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        if let client {
            let matching = [
                "PrimaryUsagePage": kHIDPage_AppleVendor,
                "PrimaryUsage": kHIDUsage_AppleVendor_TemperatureSensor,
            ]
            _ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        }
    }

    /// The sensors this reader recognizes. A product can have several services (e.g. one per die);
    /// their readings are averaged into one sensor.
    public func read() -> [TemperatureSensor] {
        var readings: [SensorKind: [Double]] = [:]
        for (name, celsius) in rawReadings() {
            guard let kind = Self.kind(forProduct: name), celsius > 0 else { continue }
            readings[kind, default: []].append(celsius)
        }
        return Self.order.compactMap { kind in
            guard let values = readings[kind], !values.isEmpty else { return nil }
            return TemperatureSensor(
                id: "hid.\(kind.rawValue)",
                kind: kind,
                label: kind == .ssd ? diskName : nil,
                celsius: values.reduce(0, +) / Double(values.count)
            )
        }
    }

    static let order: [SensorKind] = [.ssd, .batteryGasGauge, .powerManager]

    static func kind(forProduct name: String) -> SensorKind? {
        switch name {
        // One per NAND channel; all belong to the internal SSD.
        case _ where name.hasPrefix("NAND CH") && name.hasSuffix(" temp"): return .ssd
        case "gas gauge battery": return .batteryGasGauge
        case _ where name.hasPrefix("PMU tdie"): return .powerManager
        default: return nil
        }
    }

    /// Every temperature service as (product name, °C). Also used by the diagnostic dump.
    public func rawReadings() -> [(name: String, celsius: Double)] {
        guard let client, let services = IOHIDEventSystemClientCopyServices(client) as? [AnyObject] else { return [] }
        return services.compactMap { object in
            let service = unsafeBitCast(object, to: IOHIDServiceClient.self)
            guard
                let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                let event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0)
            else { return nil }
            return (name, IOHIDEventGetFloatValue(event, Int32(kIOHIDEventTypeTemperature << 16)))
        }
    }
}

// MARK: - Constants

private let kIOHIDEventTypeTemperature: Int64 = 15
private let kHIDPage_AppleVendor = 0xFF00
private let kHIDUsage_AppleVendor_TemperatureSensor = 0x0005
