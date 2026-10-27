import FanKit
import FanXPC
import Foundation
import Observation
import Security
import ServiceManagement

/// Installs the privileged helper and sends it fan commands. The app never writes to the SMC itself.
@MainActor
@Observable
final class FanControl {
    enum HelperStatus: Equatable {
        case notInstalled
        /// Registered, but the person hasn't turned it on in System Settings › General › Login Items.
        case requiresApproval
        case enabled
    }

    /// Whether the installed helper actually answers. A helper can be enabled yet fail to launch,
    /// for example when it was registered by a build with a different code signature.
    enum ConnectionState: Equatable {
        case unknown
        case checking
        case responding(version: String)
        case notResponding
    }

    private(set) var helperStatus: HelperStatus = .notInstalled
    private(set) var connectionState: ConnectionState = .unknown

    /// The last failed command per fan, shown in that fan's section.
    private(set) var errors: [Int: String] = [:]

    /// The last failed install, reinstall or removal, shown in Fan Control settings.
    private(set) var helperError: String?

    @ObservationIgnored private let monitor: HardwareMonitor
    @ObservationIgnored private let service = SMAppService.daemon(plistName: FanHelperConstants.launchDaemonPlistName)
    @ObservationIgnored private var connection: NSXPCConnection?

    init(monitor: HardwareMonitor) {
        self.monitor = monitor
        refreshStatus()
        Task { await updateHelperIfNeeded() }
    }

    // MARK: State

    func refreshStatus() {
        switch service.status {
        case .enabled: helperStatus = .enabled
        case .requiresApproval: helperStatus = .requiresApproval
        default: helperStatus = .notInstalled
        }
    }

    // MARK: Fan commands

    // Which fan runs how is decided by ProfileStore; these only deliver the command.

    /// Puts `fan` in manual mode at `rpm`, clamped to its range.
    @discardableResult
    func setSpeed(_ rpm: Double, for fan: Fan) async -> Bool {
        let rpm = fan.clamped(rpm)
        return await send(to: fan) { helper, reply in helper.setFanSpeed(fan.id, rpm: rpm, withReply: reply) }
    }

    @discardableResult
    func setAutomatic(_ fan: Fan) async -> Bool {
        await send(to: fan) { helper, reply in helper.setFanAutomatic(fan.id, withReply: reply) }
    }

    // MARK: Helper management

    /// Asks the helper for its version to confirm it launches and accepts our connection.
    func checkConnection() async {
        refreshStatus()
        guard helperStatus == .enabled else {
            connectionState = .unknown
            return
        }
        connectionState = .checking
        do {
            let version: String = try await request { helper, reply in helper.version(withReply: reply) }
            connectionState = .responding(version: version)
        } catch {
            connectionState = .notResponding
        }
    }

    /// After the app is updated, the old helper keeps running from memory until it exits. If its version
    /// differs from the app's, ask it to exit; launchd then starts the new binary from the app bundle on the
    /// next connection. Unlike reinstalling, this needs no new approval in System Settings.
    func updateHelperIfNeeded() async {
        refreshStatus()
        guard helperStatus == .enabled else { return }
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        guard
            let helperVersion: String = try? await request({ helper, reply in helper.version(withReply: reply) }),
            helperVersion != appVersion
        else { return }

        try? await request { helper, reply in helper.exitForUpdate { reply(()) } }
        dropConnection()
        connectionState = .unknown
    }

    /// Unregisters and registers the helper again, so launchd picks up the current build's signature.
    func reinstallHelper() async {
        helperError = nil
        guard Self.isSignedByTeam else {
            helperError = message(for: FanControlError.unsignedBuild)
            return
        }
        try? await service.unregister()
        dropConnection()
        do {
            try service.register()
        } catch {
            refreshStatus()
            // Registration "fails" until the person approves it; that case is shown as a status, not an error.
            if helperStatus != .requiresApproval {
                helperError = error.localizedDescription
            }
        }
        errors.removeAll()
        await checkConnection()
    }

    func removeHelper() async {
        helperError = nil
        do {
            try await service.unregister()
        } catch {
            helperError = error.localizedDescription
        }
        dropConnection()
        refreshStatus()
        connectionState = .unknown
    }

    // MARK: Private

    @discardableResult
    private func send(
        to fan: Fan,
        _ command: @escaping (FanHelperProtocol, @escaping (NSError?) -> Void) -> Void
    ) async -> Bool {
        do {
            try installHelperIfNeeded()
            let error: NSError? = try await request(command)
            if let error { throw error }
            errors[fan.id] = nil
            await monitor.refresh()
            return true
        } catch {
            errors[fan.id] = message(for: error)
            return false
        }
    }

    private func installHelperIfNeeded() throws {
        // Don't ask the person to approve a helper that would refuse every connection.
        guard Self.isSignedByTeam else { throw FanControlError.unsignedBuild }
        refreshStatus()
        if helperStatus == .notInstalled {
            // Registering a daemon asks the person to approve it; until then the status is .requiresApproval.
            try? service.register()
            refreshStatus()
        }
        if helperStatus == .requiresApproval {
            throw FanControlError.requiresApproval
        }
    }

    /// Sends one message to the helper and waits for its reply.
    private func request<Reply>(
        timeout: TimeInterval = 5,
        _ message: @escaping (FanHelperProtocol, @escaping (Reply) -> Void) -> Void
    ) async throws -> Reply {
        let connection = connection ?? makeConnection()
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce(continuation)
                // When launchd can't start the helper the message may never fail on its own.
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    once.resume(throwing: FanControlError.helperUnreachable(nil))
                }
                let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                    once.resume(throwing: FanControlError.helperUnreachable(error))
                }
                guard let helper = proxy as? FanHelperProtocol else {
                    once.resume(throwing: FanControlError.helperUnreachable(nil))
                    return
                }
                message(helper) { once.resume(returning: $0) }
            }
        } catch FanControlError.helperUnreachable(let error) {
            // Start from a fresh connection next time.
            dropConnection()
            throw FanControlError.helperUnreachable(error)
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: FanHelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func dropConnection() {
        connection?.invalidate()
        connection = nil
    }

    private func message(for error: Error) -> String {
        switch error {
        case FanControlError.requiresApproval:
            return String(localized: "Turn on Fan Controller in System Settings to change fan speeds.")
        case FanControlError.helperUnreachable:
            return String(localized: "The fan control helper isn’t responding. Reinstall it in Fan Control settings.")
        case FanControlError.unsignedBuild:
            return String(
                localized: "This copy isn’t signed by a developer team, so it can’t control fans. Build Fan Controller from source with your Apple ID to use fan control."
            )
        default:
            return error.localizedDescription
        }
    }
}

enum FanControlError: Error {
    case requiresApproval
    case helperUnreachable(Error?)
    /// The app has no team ID (an ad-hoc signed download), and the helper only accepts its own team's app.
    case unsignedBuild
}

extension FanControl {
    /// Whether this app is signed by a developer team, which the helper requires of its client.
    static let isSignedByTeam: Bool = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard
            SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) ==
            errSecSuccess,
            let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        else { return false }
        return !team.isEmpty
    }()
}

/// Resumes a continuation at most once; XPC replies, XPC errors and the timeout race each other.
private final class ResumeOnce<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let continuation = continuation
        self.continuation = nil
        return continuation
    }
}
