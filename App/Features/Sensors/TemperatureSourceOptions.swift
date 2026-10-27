import FanKit
import SwiftUI

/// Picker rows for every temperature source: group summaries first, then each sensor,
/// grouped like the main window. Shared by fan rules and the menu bar settings.
struct TemperatureSourceOptions<Tag: Hashable>: View {
    let snapshot: HardwareSnapshot?
    let tag: (TemperatureSource) -> Tag

    var body: some View {
        ForEach([SensorGroup.cpu, .gpu, .memory], id: \.self) { group in
            let sensors = snapshot?.sensors(in: group) ?? []
            if !sensors.isEmpty {
                Section(group.displayName) {
                    ForEach([TemperatureSource.hottest(group), .average(group)], id: \.self) { source in
                        Text(source.displayName(in: snapshot)).tag(tag(source))
                    }
                    ForEach(sensors) { sensor in
                        Text(sensor.displayName).tag(tag(.sensor(sensor.id)))
                    }
                }
            }
        }
        // Groups without a meaningful summary list their sensors only.
        ForEach([SensorGroup.disks, .other], id: \.self) { group in
            let sensors = snapshot?.sensors(in: group) ?? []
            if !sensors.isEmpty {
                Section(group.displayName) {
                    ForEach(sensors) { sensor in
                        Text(sensor.displayName).tag(tag(.sensor(sensor.id)))
                    }
                }
            }
        }
    }
}

extension TemperatureSource {
    /// Every source, grouped as in the main window: group summaries first, then each sensor.
    static func sections(in snapshot: HardwareSnapshot?) -> [(title: String, sources: [TemperatureSource])] {
        guard let snapshot else { return [] }
        return SensorGroup.allCases.compactMap { group in
            let sensors = snapshot.sensors(in: group)
            guard !sensors.isEmpty else { return nil }
            let summaries: [TemperatureSource] = group.hasAverage ? [.hottest(group), .average(group)] : []
            return (group.displayName, summaries + sensors.map { .sensor($0.id) })
        }
    }

    func displayName(in snapshot: HardwareSnapshot?) -> String {
        switch self {
        case .hottest(.cpu): return String(localized: "Hottest CPU Core")
        case .average(.cpu): return String(localized: "CPU Core Average")
        case .hottest(.gpu): return String(localized: "Hottest GPU Cluster")
        case .average(.gpu): return String(localized: "GPU Cluster Average")
        case .hottest(.memory): return String(localized: "Hottest Memory Sensor")
        case .average(.memory): return String(localized: "Memory Average")
        case .hottest(let group), .average(let group): return group.displayName
        case .sensor(let key): return snapshot?.sensors.first { $0.id == key }?.displayName ?? key
        }
    }
}
