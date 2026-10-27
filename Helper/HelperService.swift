import FanXPC
import Foundation
import os
import SMCKit

private let log = Logger(subsystem: FanHelperConstants.machServiceName, category: "helper")

/// Accepts XPC connections only from the signed Fan Controller app.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service = HelperService()

    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement = Self.clientRequirement else {
            log.error("Rejecting connection: helper was built without a team identifier")
            return false
        }
        // The system validates the client's code signature before delivering any message.
        connection.setCodeSigningRequirement(requirement)

        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { [service] in
            // The app quit or crashed: hand control back to the SMC.
            service.restoreAutomaticControl()
        }
        connection.resume()
        return true
    }

    /// `anchor apple generic` plus our identifier and team, so only our own signed app can connect.
    ///
    /// Release builds also refuse a debuggable app: other processes could inject code into it and use it
    /// to reach the helper. Release builds are signed without `get-task-allow` (see Base.xcconfig).
    private static let clientRequirement: String? = {
        let teamIdentifier = Bundle.main.object(forInfoDictionaryKey: "FCTeamIdentifier") as? String ?? ""
        guard !teamIdentifier.isEmpty else { return nil }
        var requirement = """
        anchor apple generic and identifier "\(FanHelperConstants.appBundleIdentifier)" \
        and certificate leaf[subject.OU] = "\(teamIdentifier)"
        """
        #if !DEBUG
            requirement += #" and !entitlement["com.apple.security.get-task-allow"]"#
        #endif
        return requirement
    }()
}

/// The only code in the project that writes to the SMC.
final class HelperService: NSObject, FanHelperProtocol {
    private let queue = DispatchQueue(label: "HelperService")
    private var smc: SMC?
    /// Set once an update was requested; writes are refused until the process exits.
    private var isExiting = false

    func setFanSpeed(_ fan: Int, rpm: Double, withReply reply: @escaping (NSError?) -> Void) {
        queue.async {
            reply(self.perform {
                // A speed set now would outlive this process with nobody to undo it.
                guard !self.isExiting else { throw HelperError.updating }
                let smc = try self.connection()
                // Never write a speed outside the range the fan itself reports, and refuse when it can't be read.
                guard
                    Self.fans(of: smc).contains(fan),
                    let target = FanLimits.target(
                        rpm: rpm,
                        minimum: smc.readDouble(.fanMinimum(fan)),
                        maximum: smc.readDouble(.fanMaximum(fan))
                    )
                else { throw HelperError.invalidRequest }

                try smc.write(.fanMode(fan), value: 1)
                try smc.write(.fanTarget(fan), value: target)
                log.info("Fan \(fan) set to \(target, format: .fixed(precision: 0)) rpm")
            })
        }
    }

    func setFanAutomatic(_ fan: Int, withReply reply: @escaping (NSError?) -> Void) {
        queue.async {
            reply(self.perform {
                let smc = try self.connection()
                guard Self.fans(of: smc).contains(fan) else { throw HelperError.invalidRequest }
                try smc.write(.fanMode(fan), value: 0)
                log.info("Fan \(fan) returned to automatic")
            })
        }
    }

    func version(withReply reply: @escaping (String) -> Void) {
        reply(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")
    }

    func exitForUpdate(withReply reply: @escaping () -> Void) {
        log.info("Exiting so launchd can start the updated helper")
        queue.sync { isExiting = true }
        restoreAutomaticControl()
        reply()
        // Give the reply time to reach the app before the process goes away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
        }
    }

    /// Returns every fan to automatic mode. All of them, not only those this process changed:
    /// a helper from before an update may have left one manual, and only this app drives the fans.
    func restoreAutomaticControl() {
        queue.sync {
            guard let smc = try? connection() else { return }
            for fan in Self.fans(of: smc) {
                try? smc.write(.fanMode(fan), value: 0)
            }
        }
    }

    // MARK: Private

    private static func fans(of smc: SMC) -> Range<Int> {
        FanLimits.indices(count: smc.readDouble(.fanCount))
    }

    private func connection() throws -> SMC {
        if let smc { return smc }
        let smc = try SMC()
        self.smc = smc
        return smc
    }

    private func perform(_ work: () throws -> Void) -> NSError? {
        do {
            try work()
            return nil
        } catch {
            log.error("SMC write failed: \(String(describing: error))")
            return NSError(
                domain: FanHelperConstants.machServiceName,
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(describing: error)]
            )
        }
    }
}

enum HelperError: Error, CustomStringConvertible {
    case updating
    /// A fan this Mac doesn't have, a speed that isn't a number, or a fan whose range can't be read.
    case invalidRequest

    var description: String {
        switch self {
        case .updating: return "The helper is restarting for an update"
        case .invalidRequest: return "The request names no valid fan or speed"
        }
    }
}
