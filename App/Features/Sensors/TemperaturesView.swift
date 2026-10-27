import FanKit
import SwiftUI

/// Every temperature in a sortable table (HIG › Lists and tables › Desktop), either grouped by component
/// under CPU, GPU and Other Sensors headers with their averages, or as one flat list.
struct TemperaturesView: View {
    let snapshot: HardwareSnapshot
    let thermalState: ProcessInfo.ThermalState

    @AppStorage(TemperaturesView.groupedKey) private var isGrouped = true
    @AppStorage(TemperatureUnit.storageKey) private var unit = TemperatureUnit.automatic
    @State private var sortOrder = [KeyPathComparator(\TemperatureTableRow.order)]
    static let groupedKey = "temperaturesGroupedByComponent"

    var body: some View {
        VStack(spacing: 0) {
            ThermalStateLabel(state: thermalState)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            Group {
                if isGrouped {
                    groupedTable
                } else {
                    flatTable
                }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle("Temperatures")
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $isGrouped) {
                    Label("Group by Component", systemImage: "list.bullet.indent")
                }
                .help("Group by Component")
            }
        }
    }

    // MARK: Grouped

    private var groupedTable: some View {
        Table(of: TemperatureTableRow.self, sortOrder: $sortOrder) {
            TableColumn("Sensor", value: \.name) { row in
                SensorNameCell(row: row)
            }
            .width(min: 200, ideal: 240)
            TableColumn("Temperature", value: \.sortCelsius) { row in
                temperatureCell(row)
            }
            .width(min: 90, ideal: 130)
        } rows: {
            // Sections, not DisclosureTableRow: binding its expansion made AppKit report a reentrant
            // table update on every load, which it says will become an assertion.
            ForEach(groups) { group in
                Section {
                    ForEach((group.children ?? []).sorted(using: sortOrder)) { sensor in
                        TableRow(sensor)
                    }
                } header: {
                    GroupHeader(row: group, unit: unit)
                }
            }
        }
    }

    /// One parent row per group with sensors. CPU and GPU show their average.
    private var groups: [TemperatureTableRow] {
        SensorGroup.allCases.enumerated().compactMap { index, group in
            let sensors = sensorRows(in: group)
            guard !sensors.isEmpty else { return nil }
            return TemperatureTableRow(
                id: "group.\(group.rawValue)", name: group.displayName,
                group: group, groupOrder: index,
                celsius: group.hasAverage ? snapshot.average(of: group) : nil,
                order: index, isGroup: true, isSummary: false, symbolName: group.symbolName,
                limits: group.thermalLimits, children: sensors
            )
        }
    }

    // MARK: Flat

    private var flatTable: some View {
        Table(flatRows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Sensor", value: \.name) { row in
                SensorNameCell(row: row)
            }
            .width(min: 200, ideal: 240)
            TableColumn("Group", value: \.groupOrder) { row in
                Text(row.group.displayName)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 120)
            TableColumn("Temperature", value: \.sortCelsius) { row in
                temperatureCell(row)
            }
            .width(min: 90, ideal: 130)
        }
    }

    /// Group averages first, then each sensor, in catalog order.
    private var flatRows: [TemperatureTableRow] {
        var rows: [TemperatureTableRow] = []
        for (index, group) in SensorGroup.allCases.enumerated() {
            if group.hasAverage, let average = snapshot.average(of: group) {
                rows.append(TemperatureTableRow(
                    id: "\(group.rawValue).average", name: TemperatureSource.average(group).displayName(in: snapshot),
                    group: group, groupOrder: index, celsius: average,
                    order: rows.count, isGroup: false, isSummary: true, symbolName: group.symbolName,
                    limits: group.thermalLimits, children: nil
                ))
            }
            rows += sensorRows(in: group).map { $0.renumbered(rows.count + $0.order) }
        }
        return rows
    }

    // MARK: Shared

    private func sensorRows(in group: SensorGroup) -> [TemperatureTableRow] {
        let index = SensorGroup.allCases.firstIndex(of: group) ?? 0
        return snapshot.sensors(in: group).enumerated().map { order, sensor in
            TemperatureTableRow(
                id: sensor.id, name: sensor.displayName, group: group, groupOrder: index,
                celsius: sensor.celsius, order: order, isGroup: false, isSummary: false,
                symbolName: sensor.kind.symbolName, limits: sensor.kind.thermalLimits, children: nil
            )
        }
    }

    @ViewBuilder
    private func temperatureCell(_ row: TemperatureTableRow) -> some View {
        if let celsius = row.celsius {
            HeatText(celsius: celsius, limits: row.limits, text: Temperature.format(celsius, unit: unit))
                .fontWeight(row.isGroup ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct TemperatureTableRow: Identifiable {
    let id: String
    let name: String
    let group: SensorGroup
    let groupOrder: Int
    /// `nil` for a group without an average (Other Sensors). Sorts as the coldest.
    let celsius: Double?
    /// Catalog order, the default sort.
    let order: Int
    let isGroup: Bool
    let isSummary: Bool
    let symbolName: String
    /// The limits that color this reading; `nil` for groups without a meaningful summary.
    let limits: ThermalLimits?
    let children: [TemperatureTableRow]?

    var sortCelsius: Double { celsius ?? -.infinity }

    func renumbered(_ order: Int) -> TemperatureTableRow {
        TemperatureTableRow(
            id: id, name: name, group: group, groupOrder: groupOrder, celsius: celsius,
            order: order, isGroup: isGroup, isSummary: isSummary, symbolName: symbolName, limits: limits,
            children: children
        )
    }
}

/// A group's symbol, name and, for CPU and GPU, its average.
private struct GroupHeader: View {
    let row: TemperatureTableRow
    let unit: TemperatureUnit

    var body: some View {
        HStack {
            Label(row.name, systemImage: row.symbolName)
            Spacer()
            if let celsius = row.celsius {
                HStack(spacing: 4) {
                    Text("Average")
                    HeatText(celsius: celsius, limits: row.limits, text: Temperature.format(celsius, unit: unit))
                }
            }
        }
    }
}

/// The sensor's symbol and name. Summary rows are emphasized.
private struct SensorNameCell: View {
    let row: TemperatureTableRow

    var body: some View {
        Label {
            Text(row.name)
                .fontWeight(row.isGroup ? .semibold : row.isSummary ? .medium : .regular)
        } icon: {
            Image(systemName: row.symbolName)
                .foregroundStyle(.secondary)
                // Symbols share one width so names line up.
                .frame(width: 18)
        }
    }
}

/// View › Group by Component (HIG › The menu bar › View menu).
struct TemperatureViewCommands: View {
    @AppStorage(TemperaturesView.groupedKey) private var isGrouped = true

    var body: some View {
        Toggle("Group by Component", isOn: $isGrouped)
    }
}
