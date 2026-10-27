import AppKit

/// Whether the app shows in the Dock, and which language it uses. Both are General settings.
enum AppPresence {
    static let showsDockIconKey = "showsDockIcon"
    static let showsMenuBarItemKey = "showInMenuBar"

    /// Without a Dock icon the app is a menu bar utility: no Dock tile and no app menus while it's frontmost.
    @MainActor
    static func applyDockIcon(_ shows: Bool) {
        NSApp.setActivationPolicy(shows ? .regular : .accessory)
        // Changing the policy can send the app's windows behind others; keep Settings in front.
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Applies the Dock setting before any window appears, so a hidden icon never flashes in the Dock,
/// and makes sure only one copy of the app drives the fans.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_: Notification) {
        quitOtherInstances()

        let shows = UserDefaults.standard.object(forKey: AppPresence.showsDockIconKey) as? Bool ?? true
        NSApp.setActivationPolicy(shows ? .regular : .accessory)
        _ = AppLanguage.atLaunch
    }

    /// Closing the window keeps the app running in the menu bar; Quit there (or ⌘Q) ends it.
    /// Without the menu bar item nothing would be left to reach the app, so closing quits as before.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        !(UserDefaults.standard.object(forKey: AppPresence.showsMenuBarItemKey) as? Bool ?? true)
    }

    /// Two copies each apply their own active profile, so they undo each other's fan commands: one sets a
    /// speed, the other returns the fan to automatic, over and over. Launch Services normally prevents a
    /// second copy, but Xcode's Run and `open -n` don't. The newest copy wins and asks the others to quit,
    /// which also lets the helper return their fans to automatic.
    private func quitOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = NSRunningApplication.current
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where other != current {
            other.terminate()
        }
    }
}

/// The app's own language, layered over the system's per-app language setting (`AppleLanguages`).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case turkish = "tr"

    var id: String { rawValue }

    /// Each language is named in itself, as in System Settings.
    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .english: return "English"
        case .turkish: return "Türkçe"
        }
    }

    /// Read from the app's own defaults domain only, so the system-wide language list doesn't count as a choice.
    static var current: AppLanguage {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: bundleID)?["AppleLanguages"] as? [String],
              let first = languages.first else { return .system }
        return AppLanguage(rawValue: String(first.prefix(2))) ?? .system
    }

    /// The language this run of the app uses. Captured once at launch; `current` changes as soon as
    /// the person picks another language, but the app keeps this one until it restarts.
    static let atLaunch = current

    /// Takes effect the next time the app launches.
    static func set(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    /// Quits and opens the app again, so the new language is used.
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this instance to finish quitting (and the helper to return the fans to automatic) first.
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
