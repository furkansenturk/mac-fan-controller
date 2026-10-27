import FanKit
import SwiftUI

/// The menu bar extra's panel, laid out like the system's own (Wi-Fi, Battery, Sound): a bold title,
/// small section headers, rows with round symbol badges and hover highlights, plain links at the bottom.
///
/// A panel rather than a menu because it holds live gauges and the profile list (HIG › The menu bar ›
/// Menu bar extras: a menu "unless the functionality … is too complex for a menu"). It also keeps updating
/// while open, which a menu doesn't.
struct MenuBarMenu: View {
    let monitor: HardwareMonitor
    let profiles: ProfileStore
    let thermalState: ThermalStateMonitor

    @Environment(\.openWindow) private var openWindow
    @AppStorage(TemperatureUnit.storageKey) private var unit = TemperatureUnit.automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fan Controller")
                    .font(.headline)
                Spacer()
                Text(profiles.displayName(of: profiles.active))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)

            ThermalStateLabel(state: thermalState.state, showsExplanation: thermalState.state != .nominal)
                .font(.subheadline)
                .padding(.horizontal, 6)

            if let snapshot = monitor.snapshot {
                if !snapshot.fans.isEmpty {
                    PanelSection("Fans") {
                        ForEach(snapshot.fans) { fan in
                            FanPanelRow(fan: fan)
                        }
                    }
                }

                PanelSection("Temperatures") {
                    HStack(spacing: 8) {
                        ForEach([SensorGroup.cpu, .gpu, .memory], id: \.self) { group in
                            if let hottest = snapshot.maximum(of: group) {
                                TemperatureTile(
                                    title: group.displayName,
                                    symbol: group.symbolName,
                                    celsius: hottest,
                                    limits: group.thermalLimits,
                                    text: Temperature.format(hottest, unit: unit, fractionDigits: 0)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }

            PanelSection("Profile") {
                ForEach(profiles.profiles) { profile in
                    ProfilePanelRow(profile: profile, profiles: profiles)
                }
            }

            Divider()
                .padding(.horizontal, 6)

            VStack(spacing: 0) {
                PanelLinkRow("Open Fan Controller") {
                    openWindow(id: WindowID.main)
                    NSApp.activate(ignoringOtherApps: true)
                }
                PanelLinkRow("About Fan Controller") {
                    AboutWindow.show(openWindow)
                }
                SettingsLink {
                    PanelLinkLabel(title: "Settings…")
                }
                .buttonStyle(PanelRowButtonStyle())
                PanelLinkRow("Quit Fan Controller") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(10)
        .frame(width: 300)
    }
}

// MARK: - Building blocks

/// A small bold section title over its rows, as in the system's menu bar panels.
private struct PanelSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
            content
        }
    }
}

/// A symbol in a filled circle, like the network icons in the Wi-Fi panel.
private struct SymbolBadge: View {
    let systemName: String
    var isActive = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
    }
}

private struct FanPanelRow: View {
    let fan: Fan

    var body: some View {
        HStack(spacing: 10) {
            SymbolBadge(systemName: "fan")
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(fan.position.displayName)
                    Spacer()
                    Text(fan.speedText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Gauge(value: fan.load) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(Color.accentColor)
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .animation(.default, value: fan.currentRPM)
        .accessibilityElement(children: .combine)
    }
}

private struct TemperatureTile: View {
    let title: String
    let symbol: String
    let celsius: Double
    let limits: ThermalLimits?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            HeatText(celsius: celsius, limits: limits, text: text)
                .font(.title3.weight(.semibold))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)))
        .accessibilityElement(children: .combine)
    }
}

private struct ProfilePanelRow: View {
    let profile: FanProfile
    let profiles: ProfileStore

    private var isActive: Bool { profiles.activeID == profile.id }

    /// What the profile does, not whether it can be edited: this panel is for switching.
    private var symbolName: String {
        switch profile.id {
        case FanProfile.automatic.id: return "fan"
        case FanProfile.fullSpeed.id: return "gauge.with.dots.needle.100percent"
        default: return "slider.horizontal.3"
        }
    }

    var body: some View {
        Button {
            profiles.activate(profile.id)
        } label: {
            HStack(spacing: 10) {
                SymbolBadge(systemName: symbolName, isActive: isActive)
                Text(profiles.displayName(of: profile))
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(PanelRowButtonStyle())
        .accessibilityValue(isActive ? Text("In Use") : Text(""))
    }
}

/// Plain text actions at the bottom, like "Wi-Fi Settings…".
private struct PanelLinkRow: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            PanelLinkLabel(title: title)
        }
        .buttonStyle(PanelRowButtonStyle())
    }
}

private struct PanelLinkLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Full-width rows that highlight under the pointer, as menu items do.
private struct PanelRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct HoverRow<Content: View>: View {
    let isPressed: Bool
    @ViewBuilder var content: Content

    @State private var isHovering = false

    var body: some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isPressed ? AnyShapeStyle(.tertiary) : isHovering ? AnyShapeStyle(.quaternary) :
                        AnyShapeStyle(.clear))
            )
            .onHover { isHovering = $0 }
    }
}
