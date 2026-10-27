import Foundation

/// Identifiers shared by the app, the helper and the launchd plist. Keep them in sync with
/// `Config/Base.xcconfig` and `Helper/com.furkansenturk.FanController.Helper.plist`.
public enum FanHelperConstants {
    public static let appBundleIdentifier = "com.furkansenturk.FanController"
    public static let machServiceName = "com.furkansenturk.FanController.Helper"
    public static let launchDaemonPlistName = "com.furkansenturk.FanController.Helper.plist"
}

/// The XPC contract between the app and the root helper.
///
/// Deliberately small: the helper only accepts the writes the UI needs.
/// Reads never go through the helper; the app reads the SMC directly.
@objc public protocol FanHelperProtocol {
    /// Puts `fan` in manual mode and sets its target speed. The helper clamps `rpm` to the fan's range.
    func setFanSpeed(_ fan: Int, rpm: Double, withReply reply: @escaping (NSError?) -> Void)

    /// Returns `fan` to SMC-controlled automatic mode.
    func setFanAutomatic(_ fan: Int, withReply reply: @escaping (NSError?) -> Void)

    /// The helper's bundle version, used to detect an outdated installed helper.
    func version(withReply reply: @escaping (String) -> Void)

    /// Returns every fan to automatic, replies, then exits so launchd starts the updated binary from the
    /// app bundle on the next connection. Sent when `version` doesn't match the app's.
    ///
    /// Must exist from the first release: an older helper can't be asked to do anything it doesn't know.
    func exitForUpdate(withReply reply: @escaping () -> Void)
}
