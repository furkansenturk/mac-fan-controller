import Charts
import FanKit
import SwiftUI

/// The fan curve a Custom rule describes: flat at the minimum, a ramp between the two temperatures,
/// flat at the maximum, with a dot at the current reading. Temperatures use the person's unit.
///
/// With `onChange`, the two corners can be dragged sideways to change the temperatures. The text fields
/// below the chart stay the accessible way to set them.
struct FanCurveChart: View {
    let fan: Fan
    let rule: SensorRule
    let snapshot: HardwareSnapshot
    var onChange: ((SensorRule) -> Void)?

    @AppStorage(TemperatureUnit.storageKey) private var unit = TemperatureUnit.automatic

    private enum Handle {
        case lower
        case upper
    }

    /// The corner being dragged and where it is, in the display unit. Saved when the drag ends.
    @State private var drag: (handle: Handle, temperature: Double)?

    /// The same limits as the text fields.
    private let celsiusRange = 20.0...110.0

    /// The rule's two corner temperatures in the display unit.
    private struct Corners {
        let lower: Double
        let upper: Double
        let unit: UnitTemperature
    }

    private struct Point: Identifiable {
        let temperature: Double
        let rpm: Double
        var id: Double { temperature }
    }

    var body: some View {
        let displayUnit = Temperature.displayUnit(for: unit)
        let savedLower = Temperature.convert(rule.lowerCelsius, to: displayUnit)
        let savedUpper = Temperature.convert(rule.upperCelsius, to: displayUnit)
        // The axis follows the saved rule, so it stays still under the pointer while dragging.
        let margin = max((savedUpper - savedLower) * 0.4, 5)
        let domain = (savedLower - margin)...(savedUpper + margin)
        let lower = drag?.handle == .lower ? drag!.temperature : savedLower
        let upper = drag?.handle == .upper ? drag!.temperature : savedUpper

        let curve = [
            Point(temperature: domain.lowerBound, rpm: fan.minimumRPM),
            Point(temperature: lower, rpm: fan.minimumRPM),
            Point(temperature: upper, rpm: fan.maximumRPM),
            Point(temperature: domain.upperBound, rpm: fan.maximumRPM),
        ]
        // While dragging, "Now" follows the curve being drawn, not the saved one.
        let shownRule = previewRule(lower: lower, upper: upper, unit: displayUnit)
        let current = rule.celsius(in: snapshot).map { celsius in
            Point(
                temperature: min(
                    max(Temperature.convert(celsius, to: displayUnit), domain.lowerBound),
                    domain.upperBound
                ),
                rpm: fan.rpm(at: shownRule.fraction(at: celsius))
            )
        }

        Chart {
            ForEach(curve) { point in
                LineMark(x: .value("Temperature", point.temperature), y: .value("Speed", point.rpm))
                    .interpolationMethod(.linear)
                AreaMark(x: .value("Temperature", point.temperature), y: .value("Speed", point.rpm))
                    .foregroundStyle(Color.accentColor.opacity(0.12))
            }
            if onChange != nil {
                // Handles: hollow so they read as something to grab, not as a reading.
                PointMark(x: .value("Temperature", lower), y: .value("Speed", fan.minimumRPM))
                    .symbol(.circle.strokeBorder(lineWidth: 2))
                    .symbolSize(110)
                PointMark(x: .value("Temperature", upper), y: .value("Speed", fan.maximumRPM))
                    .symbol(.circle.strokeBorder(lineWidth: 2))
                    .symbolSize(110)
            }
            if let current {
                PointMark(x: .value("Temperature", current.temperature), y: .value("Speed", current.rpm))
                    .symbolSize(80)
                    .annotation(position: .top, alignment: .center) {
                        // The speed shows while dragging, so the effect is visible before letting go.
                        Text(drag == nil ? String(localized: "Now") :
                            String(localized: "Now · \(Fan.rpmText(current.rpm))"))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...fan.maximumRPM * 1.05)
        .chartXAxis {
            AxisMarks(values: [lower, upper]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let degrees = value.as(Double.self) {
                        Text("\(degrees.formatted(.number.precision(.fractionLength(0))))\(displayUnit.symbol)")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [fan.minimumRPM, fan.maximumRPM]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rpm = value.as(Double.self) {
                        Text(rpm.formatted(.number.precision(.fractionLength(0))))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            if onChange != nil {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    let saved = Corners(lower: savedLower, upper: savedUpper, unit: displayUnit)
                                    dragChanged(value, proxy: proxy, geometry: geometry, saved: saved)
                                }
                                .onEnded { _ in dragEnded(unit: displayUnit) }
                        )
                        .help("Drag the circles to change the temperatures")
                }
            }
        }
        .frame(height: 140)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Fan curve"))
        .accessibilityValue(Text(accessibilityDescription(
            lower: lower,
            upper: upper,
            unit: displayUnit,
            current: current
        )))
    }

    // MARK: Dragging

    /// The rule as currently drawn, with the corners where they are on screen.
    private func previewRule(lower: Double, upper: Double, unit: UnitTemperature) -> SensorRule {
        var preview = rule
        preview.lowerCelsius = Measurement(value: lower, unit: unit).converted(to: .celsius).value
        preview.upperCelsius = Measurement(value: upper, unit: unit).converted(to: .celsius).value
        return preview
    }

    private func dragChanged(_ value: DragGesture.Value, proxy: ChartProxy, geometry: GeometryProxy, saved: Corners) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        guard let temperature = proxy.value(atX: value.location.x - origin.x, as: Double.self) else { return }

        // The corner nearest to where the drag started is the one that moves.
        let handle: Handle
        if let current = drag?.handle {
            handle = current
        } else if let start = proxy.value(atX: value.startLocation.x - origin.x, as: Double.self) {
            handle = abs(start - saved.lower) <= abs(start - saved.upper) ? .lower : .upper
        } else {
            return
        }

        let minimum = Temperature.convert(celsiusRange.lowerBound, to: saved.unit)
        let maximum = Temperature.convert(celsiusRange.upperBound, to: saved.unit)
        let rounded = temperature.rounded()
        // Keep the corners at least one degree apart and inside the limits.
        let clamped = switch handle {
        case .lower: min(max(rounded, minimum), saved.upper - 1)
        case .upper: max(min(rounded, maximum), saved.lower + 1)
        }
        drag = (handle, clamped)
    }

    private func dragEnded(unit: UnitTemperature) {
        guard let drag, let onChange else { return }
        let celsius = Measurement(value: drag.temperature, unit: unit).converted(to: .celsius).value
        var updated = rule
        switch drag.handle {
        case .lower: updated.lowerCelsius = celsius
        case .upper: updated.upperCelsius = celsius
        }
        self.drag = nil
        onChange(updated)
    }

    private func accessibilityDescription(
        lower: Double,
        upper: Double,
        unit: UnitTemperature,
        current: Point?
    ) -> String {
        let range =
            String(
                localized: "Minimum speed up to \(Int(lower))\(unit.symbol), maximum speed from \(Int(upper))\(unit.symbol)."
            )
        guard let current else { return range }
        return range + " " + String(localized: "Now \(Fan.rpmText(current.rpm)).")
    }
}
