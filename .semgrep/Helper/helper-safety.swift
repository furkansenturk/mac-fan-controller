// Fixtures for helper-safety.yml (semgrep scan --test .semgrep). Not compiled. The `ruleid` cases are the helper code before the
// security review; the `ok` cases are the code that replaced it.

final class UnsafeHelper: NSObject, NSXPCListenerDelegate {
    // ruleid: helper-accepts-connection-without-code-signing-requirement
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.resume()
        return true
    }

    func setFanSpeed(_ fan: Int, rpm: Double, withReply reply: @escaping (NSError?) -> Void) {
        // ruleid: helper-fan-index-not-checked
        let minimum = smc.readDouble(.fanMinimum(fan)) ?? rpm
        // ruleid: helper-fan-index-not-checked
        let maximum = smc.readDouble(.fanMaximum(fan)) ?? rpm
        let target = min(max(rpm, minimum), maximum)
        // ruleid: helper-fan-index-not-checked
        try smc.write(.fanMode(fan), value: 1)
        // ruleid: helper-unvalidated-fan-target, helper-fan-index-not-checked
        try smc.write(.fanTarget(fan), value: target)
        // ruleid: helper-unchecked-numeric-conversion
        log.info("Fan \(fan) set to \(Int(target)) rpm")
    }

    func restoreAutomaticControl() {
        // ruleid: helper-unchecked-numeric-conversion
        let fanCount = Int(smc.readDouble(.fanCount) ?? 0)
        for fan in 0 ..< fanCount {
            try? smc.write(.fanMode(fan), value: 0)
        }
    }
}

final class SafeHelper: NSObject, NSXPCListenerDelegate {
    // ok: helper-accepts-connection-without-code-signing-requirement
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement = Self.clientRequirement else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.resume()
        return true
    }

    func setFanSpeed(_ fan: Int, rpm: Double, withReply reply: @escaping (NSError?) -> Void) {
        let smc = try self.connection()
        guard
            Self.fans(of: smc).contains(fan),
            let target = FanLimits.target(
                rpm: rpm,
                // ok: helper-fan-index-not-checked
                minimum: smc.readDouble(.fanMinimum(fan)),
                // ok: helper-fan-index-not-checked
                maximum: smc.readDouble(.fanMaximum(fan))
            )
        else { throw HelperError.invalidRequest }

        // ok: helper-fan-index-not-checked
        try smc.write(.fanMode(fan), value: 1)
        // ok: helper-unvalidated-fan-target, helper-fan-index-not-checked
        try smc.write(.fanTarget(fan), value: target)
        log.info("Fan \(fan) set to \(target, format: .fixed(precision: 0)) rpm")
    }

    func setFanAutomatic(_ fan: Int, withReply reply: @escaping (NSError?) -> Void) {
        let smc = try self.connection()
        guard Self.fans(of: smc).contains(fan) else { throw HelperError.invalidRequest }
        // ok: helper-fan-index-not-checked
        try smc.write(.fanMode(fan), value: 0)
    }
}

// The same delegate method as SwiftFormat writes it, with the unused listener argument unnamed.
final class UnnamedArgumentHelper: NSObject, NSXPCListenerDelegate {
    // ruleid: helper-accepts-connection-without-code-signing-requirement
    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.resume()
        return true
    }
}

final class UnnamedArgumentSafeHelper: NSObject, NSXPCListenerDelegate {
    // ok: helper-accepts-connection-without-code-signing-requirement
    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(requirement)
        connection.resume()
        return true
    }
}
