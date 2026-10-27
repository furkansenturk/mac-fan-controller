import FanKit
import SwiftUI

/// What the menu bar item shows, chosen in Settings › Menu Bar.
enum MenuBarPreferences {
    static let showsIconKey = "menuBarShowsIcon"
    static let temperatureSourceKey = "menuBarTemperatureSource"
    static let fansKey = "menuBarFans"
}

/// The temperature the menu bar shows, or none. Stored as the source's raw value or "none".
struct MenuBarTemperature: RawRepresentable, Hashable {
    var source: TemperatureSource?

    init(_ source: TemperatureSource?) {
        self.source = source
    }

    init?(rawValue: String) {
        source = TemperatureSource(rawValue: rawValue)
    }

    var rawValue: String {
        source?.rawValue ?? "none"
    }
}

/// The fans whose speed the menu bar shows, stored as "0,1".
struct MenuBarFanSelection: RawRepresentable, Equatable {
    var fanIDs: Set<Int>

    init(fanIDs: Set<Int> = []) {
        self.fanIDs = fanIDs
    }

    init?(rawValue: String) {
        fanIDs = Set(rawValue.split(separator: ",").compactMap { Int($0) })
    }

    var rawValue: String {
        fanIDs.sorted().map(String.init).joined(separator: ",")
    }
}

/// The menu bar item: an optional fan symbol, an optional temperature and optional fan speeds.
struct MenuBarLabel: View {
    let monitor: HardwareMonitor

    @AppStorage(MenuBarPreferences.showsIconKey) private var showsIcon = true
    @AppStorage(MenuBarPreferences.temperatureSourceKey) private var temperature = MenuBarTemperature(.hottest(.cpu))
    @AppStorage(MenuBarPreferences.fansKey) private var fans = MenuBarFanSelection()
    @AppStorage(TemperatureUnit.storageKey) private var unit = TemperatureUnit.automatic

    var body: some View {
        let text = readout
        HStack(spacing: 4) {
            // Never leave the item empty: it would vanish from the menu bar with no way back in.
            if showsIcon || text.isEmpty {
                Image("MenuBarIcon")
            }
            if !text.isEmpty {
                Text(text)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Fan Controller"))
        .accessibilityValue(Text(text))
    }

    /// e.g. "62°C  2.298 · 2.507 rpm", in whole numbers to keep the item narrow.
    private var readout: String {
        guard let snapshot = monitor.snapshot else { return "" }
        var parts: [String] = []
        if let celsius = temperature.source?.celsius(in: snapshot) {
            parts.append(Temperature.format(celsius, unit: unit, fractionDigits: 0))
        }
        let speeds = snapshot.fans
            .filter { fans.fanIDs.contains($0.id) }
            .map { $0.currentRPM.formatted(.number.precision(.fractionLength(0))) }
        if !speeds.isEmpty {
            parts.append(String(localized: "\(speeds.joined(separator: " · ")) rpm"))
        }
        return parts.joined(separator: "  ")
    }
}
