import FanKit
import Observation

/// Polls the SMC and publishes the latest snapshot to every window and the menu bar extra.
@MainActor
@Observable
final class HardwareMonitor {
    enum State {
        case loading
        case ready(HardwareSnapshot)
        case failed(String)
    }

    private(set) var state: State = .loading

    var snapshot: HardwareSnapshot? {
        if case .ready(let snapshot) = state { return snapshot }
        return nil
    }

    /// Called with every new snapshot: ProfileStore drives the fans, AlertMonitor checks the alerts.
    @ObservationIgnored private var snapshotHandlers: [(HardwareSnapshot) -> Void] = []

    @ObservationIgnored private var reader: HardwareReader?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(interval: Duration = .seconds(2)) {
        task = Task { [weak self] in
            do {
                self?.reader = try HardwareReader()
            } catch {
                self?.state = .failed(String(describing: error))
                return
            }

            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    deinit {
        task?.cancel()
    }

    func addSnapshotHandler(_ handler: @escaping (HardwareSnapshot) -> Void) {
        snapshotHandlers.append(handler)
    }

    /// Reads a new snapshot now, e.g. right after a fan command, instead of waiting for the next poll.
    func refresh() async {
        guard let reader else { return }
        let snapshot = await reader.snapshot()
        state = .ready(snapshot)
        snapshotHandlers.forEach { $0(snapshot) }
    }
}
