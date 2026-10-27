import FanXPC
import Foundation

// FanHelper runs as root via launchd (SMAppService.daemon) and exposes FanHelperProtocol over XPC.
// It is intentionally tiny: everything it does is in HelperService.swift.

let delegate = HelperListenerDelegate()
// A previous instance may have crashed with a fan in manual mode. Start from automatic, before the first
// request; the app re-applies its profile right after.
delegate.service.restoreAutomaticControl()

let listener = NSXPCListener(machServiceName: FanHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

// Never leave fans pinned to a manual speed when launchd stops the helper.
signal(SIGTERM, SIG_IGN)
let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminationSource.setEventHandler {
    delegate.service.restoreAutomaticControl()
    exit(0)
}

terminationSource.resume()

dispatchMain()
