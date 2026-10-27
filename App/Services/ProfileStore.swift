import FanKit
import Foundation
import Observation

/// Keeps the fan profiles, remembers the active one and drives the fans to match it on every reading.
@MainActor
@Observable
final class ProfileStore {
    /// Built-in profiles first, then the person's own in the order they were made.
    private(set) var profiles: [FanProfile]
    private(set) var activeID: UUID

    @ObservationIgnored private let monitor: HardwareMonitor
    @ObservationIgnored private let control: FanControl
    @ObservationIgnored private let defaults: UserDefaults

    /// Fans with a command on its way, so a slow helper doesn't receive duplicates.
    @ObservationIgnored private var inFlight: Set<Int> = []
    /// The temperature each sensor-based fan last followed, for hysteresis.
    @ObservationIgnored private var followedCelsius: [Int: Double] = [:]
    /// When a fan's last command failed; it is retried after `retryInterval`.
    @ObservationIgnored private var lastFailure: [Int: Date] = [:]
    private let retryInterval: TimeInterval = 10
    /// Smaller target changes are inaudible and not worth an XPC round trip.
    private let rpmTolerance: Double = 50

    private enum Key {
        static let customProfiles = "customProfiles"
        /// The built-in Custom profile's rules; its name and ID never change.
        static let workingProfile = "workingProfile"
        static let activeProfile = "activeProfileID"
    }

    init(monitor: HardwareMonitor, control: FanControl, defaults: UserDefaults = .standard) {
        self.monitor = monitor
        self.control = control
        self.defaults = defaults

        let custom = defaults.data(forKey: Key.customProfiles)
            .flatMap { try? JSONDecoder().decode([FanProfile].self, from: $0) } ?? []
        let working = defaults.data(forKey: Key.workingProfile)
            .flatMap { try? JSONDecoder().decode(FanProfile.self, from: $0) }
            .map { FanProfile(
                id: FanProfile.custom.id,
                name: FanProfile.custom.name,
                defaultRule: $0.defaultRule,
                rules: $0.rules
            ) }
            ?? .custom
        let all = [FanProfile.automatic, .fullSpeed, working] + custom
        profiles = all

        let storedID = defaults.string(forKey: Key.activeProfile).flatMap(UUID.init(uuidString:))
        activeID = all.first { $0.id == storedID }?.id ?? FanProfile.automatic.id

        monitor.addSnapshotHandler { [weak self] snapshot in
            self?.apply(snapshot)
        }
    }

    var active: FanProfile {
        profiles.first { $0.id == activeID } ?? .automatic
    }

    var customProfiles: [FanProfile] {
        profiles.filter { !$0.isBuiltIn }
    }

    // MARK: Choosing

    func activate(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        defaults.set(id.uuidString, forKey: Key.activeProfile)
        lastFailure.removeAll()
        if let snapshot = monitor.snapshot { apply(snapshot) }
    }

    // MARK: Editing

    // Automatic and Full Speed never change; every edit names the profile it applies to.

    func setRule(_ rule: FanRule, for fan: Int, in id: UUID) {
        update(id) { $0.rules[fan] = rule }
        if id == activeID, let snapshot = monitor.snapshot { apply(snapshot) }
    }

    /// A change made on a fan's own page. It always lands in the Custom profile: when another profile
    /// is active, Custom first takes over that profile's rules so only the changed fan behaves differently.
    func setRuleFromFanPage(_ rule: FanRule, for fan: Int) {
        let customID = FanProfile.custom.id
        if activeID != customID {
            let current = active
            update(customID) {
                $0.defaultRule = current.defaultRule
                $0.rules = current.rules
            }
            activeID = customID
            defaults.set(customID.uuidString, forKey: Key.activeProfile)
        }
        setRule(rule, for: fan, in: customID)
    }

    /// Adds a profile with every fan automatic and returns its ID so the sidebar can select it.
    @discardableResult
    func createProfile() -> UUID {
        add(FanProfile(name: uniqueName(String(localized: "New Profile"))))
    }

    /// Keeps what was set up in Custom as a profile of its own, switches to it and returns its ID.
    @discardableResult
    func saveCustomAsNewProfile() -> UUID {
        let custom = profile(FanProfile.custom.id) ?? .custom
        let id = add(FanProfile(
            name: uniqueName(String(localized: "New Profile")),
            defaultRule: custom.defaultRule,
            rules: custom.rules
        ))
        activate(id)
        return id
    }

    /// Adds a copy of `id`, e.g. to customize a built-in profile.
    @discardableResult
    func duplicate(_ id: UUID) -> UUID? {
        guard let original = profiles.first(where: { $0.id == id }) else { return nil }
        let name = uniqueName(String(localized: "\(displayName(of: original)) Copy"))
        return add(FanProfile(name: name, defaultRule: original.defaultRule, rules: original.rules))
    }

    /// Adds a profile read from a file. Its name is kept unless another profile already uses it.
    @discardableResult
    func importProfile(_ profile: FanProfile) -> UUID {
        let name = profile.name.isEmpty ? String(localized: "Imported Profile") : profile.name
        return add(FanProfile(name: uniqueName(name), defaultRule: profile.defaultRule, rules: profile.rules))
    }

    func rename(_ id: UUID, to name: String) {
        update(id) { $0.name = name }
    }

    func delete(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }), !profile.isBuiltIn else { return }
        profiles.removeAll { $0.id == id }
        save()
        if activeID == id { activate(FanProfile.automatic.id) }
    }

    func profile(_ id: UUID) -> FanProfile? {
        profiles.first { $0.id == id }
    }

    func displayName(of profile: FanProfile) -> String {
        switch profile.id {
        case FanProfile.automatic.id: return String(localized: "Automatic")
        case FanProfile.fullSpeed.id: return String(localized: "Full Speed")
        case FanProfile.custom.id: return String(localized: "Custom")
        default: return profile.name.isEmpty ? String(localized: "Untitled Profile") : profile.name
        }
    }

    // MARK: Driving the fans

    /// Brings every fan in line with the active profile. Sends a command only when something differs.
    private func apply(_ snapshot: HardwareSnapshot) {
        let profile = active
        for fan in snapshot.fans where !inFlight.contains(fan.id) {
            if let failed = lastFailure[fan.id], Date.now.timeIntervalSince(failed) < retryInterval { continue }

            let rule = profile.rule(for: fan.id)
            var celsius: Double?
            if case .sensorBased(let sensorRule) = rule, let measured = sensorRule.celsius(in: snapshot) {
                celsius = Hysteresis.effective(
                    current: measured,
                    previous: followedCelsius[fan.id],
                    band: sensorRule.hysteresisCelsius
                )
            }
            followedCelsius[fan.id] = celsius
            let target = rule.targetRPM(for: fan, in: snapshot, celsiusOverride: celsius)
            switch (target, fan.mode) {
            case (nil, .automatic):
                continue
            case (nil, .manual):
                send(to: fan) { await $0.setAutomatic(fan) }
            case (let rpm?, let mode):
                guard mode == .automatic || abs(fan.targetRPM - rpm) >= rpmTolerance else { continue }
                send(to: fan) { await $0.setSpeed(rpm, for: fan) }
            }
        }
    }

    private func send(to fan: Fan, _ command: @escaping (FanControl) async -> Bool) {
        inFlight.insert(fan.id)
        Task {
            let succeeded = await command(control)
            inFlight.remove(fan.id)
            lastFailure[fan.id] = succeeded ? nil : .now
        }
    }

    // MARK: Private

    private func add(_ profile: FanProfile) -> UUID {
        profiles.append(profile)
        save()
        return profile.id
    }

    private func update(_ id: UUID, _ change: (inout FanProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }), profiles[index].isEditable else { return }
        change(&profiles[index])
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(customProfiles), forKey: Key.customProfiles)
        defaults.set(try? JSONEncoder().encode(profile(FanProfile.custom.id)), forKey: Key.workingProfile)
    }

    /// "Custom", then "Custom 2", "Custom 3"… so profile names never collide.
    private func uniqueName(_ base: String) -> String {
        let names = Set(profiles.map(displayName(of:)))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}
