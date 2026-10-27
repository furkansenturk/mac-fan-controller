import FanKit
import SwiftUI

/// Built-in profiles, a separator, then the person's own. Used in the Fans menu and the menu bar.
struct ProfilePicker: View {
    let profiles: ProfileStore

    var body: some View {
        Picker("Profile", selection: Binding { profiles.activeID } set: { profiles.activate($0) }) {
            ForEach(FanProfile.builtIn) { profile in
                Text(profiles.displayName(of: profile)).tag(profile.id)
            }
            if !profiles.customProfiles.isEmpty {
                Divider()
                ForEach(profiles.customProfiles) { profile in
                    Text(profiles.displayName(of: profile)).tag(profile.id)
                }
            }
        }
    }
}

/// The Fans menu (HIG › The menu bar › App-specific menus). Mirrors the sidebar's profile commands.
struct FanMenuItems: View {
    let profiles: ProfileStore
    let navigation: Navigation

    @Environment(\.openWindow) private var openWindow

    /// The profile selected in the sidebar, or else the active one.
    private var targetID: UUID { navigation.selectedProfileID ?? profiles.activeID }
    private var targetIsBuiltIn: Bool { profiles.profile(targetID)?.isBuiltIn ?? true }

    var body: some View {
        ProfilePicker(profiles: profiles)
            .pickerStyle(.inline)

        Divider()

        Button("Set All Fans to Automatic") {
            profiles.activate(FanProfile.automatic.id)
        }
        .keyboardShortcut("a", modifiers: [.command, .option])
        // Stay in the menu but disabled when there is nothing to reset.
        .disabled(profiles.activeID == FanProfile.automatic.id)

        Divider()

        Button("New Profile") {
            show(.profile(profiles.createProfile()))
        }
        .keyboardShortcut("n")

        Button("Rename Profile") {
            show(.profile(targetID))
            navigation.renamingProfileID = targetID
        }
        .disabled(targetIsBuiltIn)

        Button("Duplicate Profile") {
            if let copy = profiles.duplicate(targetID) { show(.profile(copy)) }
        }
        .keyboardShortcut("d")

        Divider()

        Button("Import Profile…") {
            openWindow(id: WindowID.main)
            navigation.isImportingProfile = true
        }

        Button("Export Profile…") {
            openWindow(id: WindowID.main)
            navigation.exportingProfileID = targetID
        }

        Divider()

        // Kept in the menu but disabled for built-in profiles (HIG › The menu bar).
        Button("Delete Profile…") {
            openWindow(id: WindowID.main)
            navigation.profilePendingDeletion = targetID
        }
        .disabled(targetIsBuiltIn)
    }

    private func show(_ item: SidebarItem) {
        openWindow(id: WindowID.main)
        navigation.selection = item
    }
}
