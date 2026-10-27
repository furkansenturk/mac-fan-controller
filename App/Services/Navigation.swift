import Foundation
import Observation

/// What the sidebar can show. Shared with menu commands so New Profile can select what it made.
enum SidebarItem: Hashable {
    case fan(Int)
    case temperatures
    case profile(UUID)
    case automation
    case alerts
}

@MainActor
@Observable
final class Navigation {
    var selection: SidebarItem? = .fan(0)

    /// A profile waiting for the person to confirm its deletion.
    var profilePendingDeletion: UUID?

    /// The profile whose name is being edited in place in the sidebar.
    var renamingProfileID: UUID?

    /// The profile being saved to a file.
    var exportingProfileID: UUID?
    var isImportingProfile = false
    /// Why the last import failed, shown in an alert.
    var importError: String?

    /// The profile selected in the sidebar, if any.
    var selectedProfileID: UUID? {
        if case .profile(let id) = selection { return id }
        return nil
    }
}
