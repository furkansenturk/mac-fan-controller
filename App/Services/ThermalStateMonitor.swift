import Foundation
import Observation
import SwiftUI

/// macOS's own view of how hot the Mac is (`ProcessInfo.thermalState`), the official signal next to the
/// per-sensor limits this app estimates. Updates when macOS posts a change.
@MainActor
@Observable
final class ThermalStateMonitor {
    private(set) var state = ProcessInfo.processInfo.thermalState

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state = ProcessInfo.processInfo.thermalState
            }
        }
    }
}

extension ProcessInfo.ThermalState {
    var displayName: String {
        switch self {
        case .nominal: return String(localized: "Normal")
        case .fair: return String(localized: "Fair")
        case .serious: return String(localized: "Serious")
        case .critical: return String(localized: "Critical")
        @unknown default: return String(localized: "Unknown")
        }
    }

    /// What the state means, after Apple's documentation. Apple Silicon offers no public signal for
    /// throttling itself, so the wording stays with what macOS says each state implies.
    var explanation: String {
        switch self {
        case .nominal: return String(localized: "Temperatures are within normal limits.")
        case .fair: return String(localized: "Slightly elevated. Fans may speed up.")
        case .serious: return String(localized: "High. macOS may reduce performance to cool down.")
        case .critical: return String(localized: "Very high. macOS is reducing performance to cool down.")
        @unknown default: return ""
        }
    }

    var symbolName: String {
        switch self {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious, .critical: return "thermometer.high"
        @unknown default: return "thermometer.medium"
        }
    }

    /// On the same 0…1 scale as the sensor limits, so the sidebar dot and colors can use either.
    var severity: Double {
        switch self {
        case .nominal: return 0
        case .fair: return 0.3
        case .serious: return 0.75
        case .critical: return 1
        @unknown default: return 0
        }
    }
}

/// "macOS thermal state: Normal" with a symbol, colored like the readings, and the explanation.
struct ThermalStateLabel: View {
    let state: ProcessInfo.ThermalState
    var showsExplanation = true

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("macOS thermal state: \(state.displayName)")
                if showsExplanation {
                    Text(state.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: state.symbolName)
                .foregroundStyle(Color.heat(state.severity))
        }
        .accessibilityElement(children: .combine)
    }
}
