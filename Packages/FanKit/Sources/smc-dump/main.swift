import FanKit
import Foundation
import SMCKit

// Prints the fans and every temperature-like key this Mac exposes.
// Output is attached to "model support" reports, see docs/supported-models.md.

func model() -> String {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
    return String(cString: buffer)
}

let smc: SMC
do {
    smc = try SMC()
} catch {
    FileHandle.standardError.write(Data("smc-dump: \(error)\n".utf8))
    exit(1)
}

print("Model: \(model())")
print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
print()

let fans = FanLimits.indices(count: smc.readDouble(.fanCount))
print("Fans: \(fans.count)")
for fan in fans {
    let keys: [SMCKey] = [.fanActual(fan), .fanMinimum(fan), .fanMaximum(fan), .fanTarget(fan), .fanMode(fan)]
    let values = keys.map { key -> String in
        guard let value = try? smc.read(key) else { return "\(key)=–" }
        return "\(key)=\(value.doubleValue.map { String(format: "%.0f", $0) } ?? "?") (\(value.dataType))"
    }
    print("  Fan \(fan): " + values.joined(separator: "  "))
}

print()

print("HID temperature sensors:")
for (name, celsius) in HIDTemperatures().rawReadings().sorted(by: { $0.name < $1.name }) {
    print(String(format: "  %-24@ %7.2f", name as NSString, celsius))
}

print()

print("Temperature keys:")
for key in try smc.allKeys() where key.name.hasPrefix("T") {
    guard let value = try? smc.read(key), let celsius = value.doubleValue else { continue }
    print(String(format: "  %@  %@  %7.2f", key.name, value.dataType.name, celsius))
}
