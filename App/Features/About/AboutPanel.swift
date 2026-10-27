import AppKit
import FanKit
import SwiftUI

/// The About window (HIG › The menu bar › App menu: "Displays the About window for your app, which
/// includes copyright and version information").
///
/// Our own window rather than the standard panel: it adds what a bug report needs (chip, fan count,
/// macOS version) as selectable text, and gives the links real buttons instead of a block of credits.
struct AboutView: View {
    let monitor: HardwareMonitor

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)

            Text(Self.info("CFBundleDisplayName") ?? "Fan Controller")
                .font(.title.weight(.semibold))
                .padding(.top, 8)

            Text("Version \(Self.info("CFBundleShortVersionString") ?? "–") (\(Self.info("CFBundleVersion") ?? "–"))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)

            Text("Shows your Mac’s fan speeds and temperatures, and lets you control the fans.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            systemSummary
                .padding(.top, 18)

            HStack(spacing: 8) {
                LinkButton(title: "Website", symbol: "globe", url: Links.website)
                LinkButton(
                    title: "Source Code",
                    symbol: "chevron.left.forwardslash.chevron.right",
                    url: Links.repository
                )
            }
            .padding(.top, 18)

            if let copyright = Self.info("NSHumanReadableCopyright") {
                Text(copyright)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(width: 340)
    }

    /// This Mac, as a support request would ask for it.
    private var systemSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            SummaryRow(symbol: "cpu", text: HardwareReader.chipName())
            if let fans = monitor.snapshot?.fans.count {
                SummaryRow(symbol: "fan", text: String(localized: "\(fans) fans"))
            }
            SummaryRow(symbol: "laptopcomputer", text: Self.macOSVersion)
        }
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This Mac")
    }

    /// Read from the bundle's own `AppIcon.icns`. Asking the system (`NSWorkspace`, `applicationIconImage`)
    /// returns a blank or generic icon for an Icon Composer icon until Launch Services has indexed the build.
    private static let appIcon: NSImage =
        Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

private struct SummaryRow: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
    }
}

private struct LinkButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let url: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .help(url.absoluteString)
    }
}

/// The About menu item. A view so it can open the window from `.commands`.
struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Fan Controller") { AboutWindow.show(openWindow) }
    }
}

enum AboutWindow {
    /// Brings the app forward too: without a Dock icon it may not be active when the menu bar asks.
    @MainActor
    static func show(_ openWindow: OpenWindowAction) {
        openWindow(id: WindowID.about)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum Links {
    static let website = URL(string: "https://furkansenturk.com")!
    static let repository = URL(string: "https://github.com/furkansenturk/mac-fan-controller")!
}
