import Foundation

/// The file a profile is shared as: JSON with a format marker and version around the profile,
/// so a future version can still read today's files and other JSON is rejected clearly.
public struct ProfileExport: Codable, Equatable {
    public static let formatIdentifier = "com.furkansenturk.FanController.profile"
    public static let currentVersion = 1

    public let format: String
    public let version: Int
    public let profile: FanProfile

    public init(profile: FanProfile) {
        format = Self.formatIdentifier
        version = Self.currentVersion
        self.profile = profile
    }

    public enum ImportError: Error, Equatable {
        case notAProfile
        case newerVersion(Int)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// The profile in `data`, with a fresh ID so importing the same file twice gives two profiles.
    public static func profile(from data: Data) throws -> FanProfile {
        guard let export = try? JSONDecoder().decode(ProfileExport.self, from: data),
              export.format == formatIdentifier
        else {
            throw ImportError.notAProfile
        }
        guard export.version <= currentVersion else {
            throw ImportError.newerVersion(export.version)
        }
        let profile = export.profile
        return FanProfile(name: profile.name, defaultRule: profile.defaultRule, rules: profile.rules)
    }
}
