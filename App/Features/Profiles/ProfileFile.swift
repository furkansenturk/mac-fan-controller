import FanKit
import SwiftUI
import UniformTypeIdentifiers

/// A profile as a JSON file, for the save panel.
struct ProfileFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let profile: FanProfile

    init(profile: FanProfile) {
        self.profile = profile
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        profile = try ProfileExport.profile(from: data)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try ProfileExport(profile: profile).encoded())
    }
}

extension ProfileExport.ImportError {
    var message: String {
        switch self {
        case .notAProfile:
            return String(localized: "The file isn’t a Fan Controller profile.")
        case .newerVersion:
            return String(
                localized: "The profile was made by a newer version of Fan Controller. Update the app to import it."
            )
        }
    }
}
