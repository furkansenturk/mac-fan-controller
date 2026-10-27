import FanKit
import SwiftUI

struct FanSpeedRow: View {
    let fan: Fan

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 6) {
                Text(fan.speedText)
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundStyle(fan.isStopped ? .secondary : .primary)
                    .contentTransition(.numericText())
                Gauge(value: fan.load) {
                    EmptyView()
                }
                .gaugeStyle(.linearCapacity)
                // Accent, not green: the bar shows effort, not health.
                .tint(Color.accentColor)
                .frame(width: 120)
                .accessibilityHidden(true)
            }
        } label: {
            Text("Speed")
            Text(fan.rangeText)
        }
        .padding(.vertical, 2)
        .animation(.default, value: fan.currentRPM)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Display

extension FanPosition {
    var displayName: String {
        switch self {
        case .only: return String(localized: "Fan")
        case .left: return String(localized: "Left Fan")
        case .right: return String(localized: "Right Fan")
        case .numbered(let number): return String(localized: "Fan \(number)")
        }
    }
}

extension Fan {
    /// Apple Silicon fans stop entirely at low load; "Stopped" reads better than "0 rpm".
    var isStopped: Bool { currentRPM < 1 }

    var speedText: String {
        isStopped ? String(localized: "Stopped") : Self.rpmText(currentRPM)
    }

    var rangeText: String {
        String(localized: "\(Self.format(minimumRPM))–\(Self.format(maximumRPM)) rpm")
    }

    static func rpmText(_ rpm: Double) -> String {
        String(localized: "\(format(rpm)) rpm")
    }

    private static func format(_ rpm: Double) -> String {
        rpm.formatted(.number.precision(.fractionLength(0)))
    }
}
