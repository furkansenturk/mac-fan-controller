import FanKit
import SwiftUI

/// Control › Manual: a constant speed, set with a slider over the fan's range.
struct ConstantSpeedRow: View {
    let fan: Fan
    let fraction: Double
    let commit: (Double) -> Void

    /// The value while dragging; saved and sent once the slider rests.
    @State private var editing: Double?

    var body: some View {
        let rpm = fan.rpm(at: editing ?? fraction)
        LabeledContent("Target speed") {
            HStack(spacing: 12) {
                Slider(value: binding, in: 0...1) {
                    Text("Target speed")
                }
                .labelsHidden()
                .frame(minWidth: 140, maxWidth: 220)
                .help(Fan.rpmText(rpm))

                Text(Fan.rpmText(rpm))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 80, alignment: .trailing)
            }
        }
        .task(id: editing) {
            guard let editing else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            commit(editing)
            self.editing = nil
        }
    }

    private var binding: Binding<Double> {
        Binding {
            editing ?? fraction
        } set: { newValue in
            // Whole 50 rpm steps: finer than that is inaudible.
            let rpm = (fan.rpm(at: newValue) / 50).rounded() * 50
            editing = fan.fraction(of: rpm)
        }
    }
}

/// Control › Custom: which temperature to follow and between which temperatures to ramp up.
struct SensorRuleRows: View {
    let fan: Fan
    let snapshot: HardwareSnapshot
    let sensorRule: SensorRule
    let commit: (SensorRule) -> Void

    @AppStorage(TemperatureUnit.storageKey) private var unit = TemperatureUnit.automatic

    var body: some View {
        // One menu with check marks: several sensors can be followed at once.
        LabeledContent {
            Menu {
                ForEach(TemperatureSource.sections(in: snapshot), id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.sources, id: \.self) { source in
                            Toggle(source.displayName(in: snapshot), isOn: selectionBinding(source))
                                // At least one sensor stays selected.
                                .disabled(sensorRule.sources == [source])
                        }
                    }
                }
            } label: {
                Text(selectionSummary)
            }
            .fixedSize()
        } label: {
            Text("Sensors")
            Text("Uses the highest temperature of the selected sensors.")
        }

        TemperatureField(title: "Start increasing at", celsius: lowerBinding)
        TemperatureField(title: "Maximum speed at", celsius: upperBinding)
        TemperatureDifferenceField(title: "Slow down after cooling by", celsius: hysteresisBinding)
            .help(
                "Keeps the fan from speeding up and slowing down over and over while the temperature hovers around one value."
            )

        LabeledContent("Now") {
            Text(nowText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// e.g. "56,2°C → 2.940 rpm", so the effect of the two temperatures is visible right away.
    private var nowText: String {
        guard fan.hasKnownRange else {
            return String(localized: "Speed range unavailable, controlled by macOS")
        }
        guard let celsius = sensorRule.celsius(in: snapshot) else {
            return String(localized: "No reading, running at maximum speed")
        }
        let rpm = FanRule.sensorBased(sensorRule).targetRPM(for: fan, in: snapshot) ?? fan.maximumRPM
        return "\(Temperature.format(celsius, unit: unit)) → \(Fan.rpmText(rpm))"
    }

    /// One sensor's name, or "3 sensors".
    private var selectionSummary: String {
        let sources = sensorRule.sources
        return sources.count == 1
            ? sources[0].displayName(in: snapshot)
            : String(localized: "\(sources.count) sensors")
    }

    /// The first selected sensor is stored as `source`, the rest as `extraSources`.
    private func selectionBinding(_ source: TemperatureSource) -> Binding<Bool> {
        Binding {
            sensorRule.sources.contains(source)
        } set: { isOn in
            var sources = sensorRule.sources.filter { $0 != source }
            if isOn { sources.append(source) }
            guard let first = sources.first else { return }
            var rule = sensorRule
            rule.source = first
            rule.extraSources = Array(sources.dropFirst())
            commit(rule)
        }
    }

    private var hysteresisBinding: Binding<Double> {
        Binding { sensorRule.hysteresisCelsius } set: {
            var rule = sensorRule
            rule.hysteresisCelsius = $0
            commit(rule)
        }
    }

    /// The two temperatures always stay at least one degree apart.
    private var lowerBinding: Binding<Double> {
        Binding { sensorRule.lowerCelsius } set: {
            var rule = sensorRule
            rule.lowerCelsius = $0
            rule.upperCelsius = max(rule.upperCelsius, $0 + 1)
            commit(rule)
        }
    }

    private var upperBinding: Binding<Double> {
        Binding { sensorRule.upperCelsius } set: {
            var rule = sensorRule
            rule.upperCelsius = $0
            rule.lowerCelsius = min(rule.lowerCelsius, $0 - 1)
            commit(rule)
        }
    }
}

/// A temperature typed or stepped in the person's unit and stored in Celsius.
struct TemperatureField: View {
    let title: LocalizedStringKey
    @Binding var celsius: Double

    @AppStorage(TemperatureUnit.storageKey) private var unit = TemperatureUnit.automatic

    /// Fans are pointless below room temperature and Apple Silicon throttles before 110 °C.
    private let celsiusRange = 20.0...110.0

    var body: some View {
        let displayUnit = Temperature.displayUnit(for: unit)
        let range = Temperature.convert(celsiusRange.lowerBound, to: displayUnit)...Temperature.convert(
            celsiusRange.upperBound,
            to: displayUnit
        )
        let value = Binding<Double> {
            Temperature.convert(celsius, to: displayUnit).rounded()
        } set: {
            let clamped = min(max($0, range.lowerBound), range.upperBound)
            celsius = Measurement(value: clamped, unit: displayUnit).converted(to: .celsius).value
        }

        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                Stepper(title, value: value, in: range, step: 1)
                    .labelsHidden()
                Text(displayUnit.symbol)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A temperature difference, such as the hysteresis band, in the person's unit. Unlike `TemperatureField`
/// it converts without an offset: 3 °C of difference is 5.4 °F, not 37.4 °F.
struct TemperatureDifferenceField: View {
    let title: LocalizedStringKey
    @Binding var celsius: Double

    @AppStorage(TemperatureUnit.storageKey) private var unit = TemperatureUnit.automatic

    var body: some View {
        let displayUnit = Temperature.displayUnit(for: unit)
        let factor = displayUnit == .fahrenheit ? 1.8 : 1
        let value = Binding<Double> {
            (celsius * factor).rounded()
        } set: {
            celsius = min(max($0, 0), 10 * factor) / factor
        }

        LabeledContent(title) {
            HStack(spacing: 4) {
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0))))
                    .monospacedDigit()
                Stepper(title, value: value, in: 0...(10 * factor).rounded(), step: 1)
                    .labelsHidden()
                Text(displayUnit.symbol)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
