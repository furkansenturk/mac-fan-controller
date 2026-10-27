@testable import FanKit
import XCTest

private func fan(min: Double = 1200, max: Double = 5200, current: Double = 2000) -> Fan {
    Fan(id: 0, position: .left, currentRPM: current, minimumRPM: min, maximumRPM: max, targetRPM: 0, mode: .automatic)
}

private func cpu(_ celsius: Double...) -> HardwareSnapshot {
    HardwareSnapshot(fans: [fan()], sensors: celsius.enumerated().map { index, value in
        TemperatureSensor(id: "Tp0\(index)", kind: .performanceCore, number: index + 1, celsius: value)
    })
}

final class FanReadingScenarioTests: XCTestCase {
    func testInvertedRangeNeverExceedsTheMaximum() {
        let inverted = fan(min: 5000, max: 1000)
        XCTAssertEqual(inverted.clamped(3000), 1000)
        XCTAssertEqual(inverted.load, 0)
        XCTAssertEqual(inverted.fraction(of: 3000), 0)
    }

    func testOutOfRangeConstantsAreHeldToTheFansRange() {
        XCTAssertEqual(FanRule.constant(fraction: 5).targetRPM(for: fan(), in: cpu(50)), 5200)
        XCTAssertEqual(FanRule.constant(fraction: -5).targetRPM(for: fan(), in: cpu(50)), 1200)
    }

    func testPositionForIndicesBeyondTheCount() {
        XCTAssertEqual(FanPosition(index: 2, count: 2), .numbered(3))
        XCTAssertEqual(FanPosition(index: 5, count: 1), .only)
    }
}

final class TemperatureScenarioTests: XCTestCase {
    func testBelowFreezingReadingsAverageCorrectly() {
        XCTAssertEqual(cpu(-5, 5).average(of: .cpu), 0)
        XCTAssertEqual(cpu(-5, -10).maximum(of: .cpu), -5)
    }

    func testDuplicateSensorIDsResolveToTheFirst() {
        let snapshot = HardwareSnapshot(fans: [], sensors: [
            TemperatureSensor(id: "Tp01", kind: .performanceCore, celsius: 40),
            TemperatureSensor(id: "Tp01", kind: .performanceCore, celsius: 90),
        ])
        XCTAssertEqual(TemperatureSource.sensor("Tp01").celsius(in: snapshot), 40)
    }

    func testRawValueParsingIsStrict() {
        for raw in ["cpu.hottest.extra", "CPU.hottest", " cpu.hottest", "cpu.hottest ", "cpu..hottest", "sensor"] {
            XCTAssertNil(TemperatureSource(rawValue: raw), raw)
        }
    }

    func testUnusualSensorKeysRoundTrip() {
        for key in ["", "Tç01", "hid.ssd.0", "sensor.nested"] {
            let source = TemperatureSource.sensor(key)
            XCTAssertEqual(TemperatureSource(rawValue: source.rawValue), source, key)
        }
    }

    func testFractionAtInfiniteTemperatures() {
        XCTAssertEqual(SensorRule.default.fraction(at: .infinity), 1)
        XCTAssertEqual(SensorRule.default.fraction(at: -.infinity), 0)
    }

    func testFractionExactlyAtTheEnds() {
        XCTAssertEqual(SensorRule.default.fraction(at: 50), 0)
        XCTAssertEqual(SensorRule.default.fraction(at: 80), 1)
        XCTAssertEqual(SensorRule.default.fraction(at: 65), 0.5)
    }

    func testDuplicatedSourcesDontChangeTheReading() {
        let rule = SensorRule(
            source: .hottest(.cpu),
            extraSources: [.hottest(.cpu), .hottest(.cpu)],
            lowerCelsius: 40,
            upperCelsius: 80
        )
        XCTAssertEqual(rule.celsius(in: cpu(55, 61)), 61)
    }

    func testRuleFollowsTheOnlySourceWithAReading() {
        let rule = SensorRule(
            source: .sensor("missing"),
            extraSources: [.average(.cpu)],
            lowerCelsius: 40,
            upperCelsius: 80
        )
        XCTAssertEqual(rule.targetRPM(for: fan(), in: cpu(60)), 3200)
    }
}

private extension SensorRule {
    func targetRPM(for fan: Fan, in snapshot: HardwareSnapshot) -> Double? {
        FanRule.sensorBased(self).targetRPM(for: fan, in: snapshot)
    }
}

final class HysteresisScenarioTests: XCTestCase {
    /// A slow cool-down: the fan holds until the drop reaches the band, then follows in one step.
    func testSlowCoolDownSequence() throws {
        var followed: Double?
        var history: [Double] = []
        for reading in [70.0, 69, 68, 67.5, 67, 66, 64] {
            followed = Hysteresis.effective(current: reading, previous: followed, band: 3)
            try history.append(XCTUnwrap(followed))
        }
        XCTAssertEqual(history, [70, 70, 70, 70, 67, 67, 64])
    }

    func testOscillationAroundOneValueKeepsTheSpeedSteady() {
        var followed: Double? = 70
        for reading in [69.0, 70, 68.5, 70, 69] {
            followed = Hysteresis.effective(current: reading, previous: followed, band: 3)
            XCTAssertEqual(followed, 70)
        }
    }

    func testHugeBandHoldsUntilTheTemperatureRises() {
        XCTAssertEqual(Hysteresis.effective(current: 20, previous: 90, band: 1000), 90)
        XCTAssertEqual(Hysteresis.effective(current: 91, previous: 90, band: 1000), 91)
    }
}

final class AutomationScenarioTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()

    func testDisabledFirstRuleFallsThrough() {
        let rules = [
            AutomationRule(condition: .onBattery, profileID: first, isEnabled: false),
            AutomationRule(condition: .onBattery, profileID: second),
        ]
        let context = AutomationContext(isOnBattery: true, runningBundleIDs: [])
        XCTAssertEqual(
            Automation.matchingRule(in: rules, context: context, existingProfiles: [first, second])?.profileID,
            second
        )
    }

    func testNoExistingProfilesMatchNothing() {
        let rules = [AutomationRule(condition: .onBattery, profileID: first)]
        XCTAssertNil(Automation.matchingRule(
            in: rules,
            context: .init(isOnBattery: true, runningBundleIDs: []),
            existingProfiles: []
        ))
    }

    func testBundleIDsAreCaseSensitive() {
        let rules = [AutomationRule(
            condition: .appRunning(bundleID: "com.apple.FinalCut", name: "Final Cut Pro"),
            profileID: first
        )]
        let context = AutomationContext(isOnBattery: false, runningBundleIDs: ["com.apple.finalcut"])
        XCTAssertNil(Automation.matchingRule(in: rules, context: context, existingProfiles: [first]))
    }

    func testUnicodeAppNamesRoundTrip() throws {
        let rules = [AutomationRule(
            condition: .appRunning(bundleID: "com.example.Oyun", name: "Oyun 🎮 Çılgın"),
            profileID: first
        )]
        XCTAssertEqual(try JSONDecoder().decode([AutomationRule].self, from: JSONEncoder().encode(rules)), rules)
    }
}

final class TemperatureAlertScenarioTests: XCTestCase {
    func testBelowFreezingThreshold() {
        let alert = TemperatureAlert(source: .sensor("TB0T"), thresholdCelsius: 3)
        XCTAssertEqual(alert.transition(celsius: 4, armed: true), .fire)
        XCTAssertNil(alert.transition(celsius: -1.9, armed: false))
        XCTAssertEqual(alert.transition(celsius: -2, armed: false), .rearm)
    }

    func testSpikeAndDropSequenceNotifiesTwice() {
        let alert = TemperatureAlert(source: .hottest(.cpu), thresholdCelsius: 90)
        var armed = true
        var fired = 0
        for reading in [80.0, 95, 99, 88, 91, 84, 92] {
            switch alert.transition(celsius: reading, armed: armed) {
            case .fire: fired += 1; armed = false
            case .rearm: armed = true
            case nil: break
            }
        }
        XCTAssertEqual(fired, 2)
    }

    func testNaNReadingChangesNothing() {
        let alert = TemperatureAlert(source: .hottest(.cpu), thresholdCelsius: 90)
        XCTAssertNil(alert.transition(celsius: .nan, armed: true))
        XCTAssertNil(alert.transition(celsius: .nan, armed: false))
    }
}

final class ThermalLimitsScenarioTests: XCTestCase {
    func testInvertedLimitsAreStillWellDefined() {
        let limits = ThermalLimits(warmCelsius: 80, criticalCelsius: 60)
        XCTAssertEqual(limits.severity(at: 70), 1)
        XCTAssertEqual(limits.severity(at: 50), 0)
    }

    func testSeverityIsMonotonic() {
        for kind in SensorKind.allCases {
            let values = stride(from: 0.0, through: 120, by: 0.5).map(kind.thermalLimits.severity(at:))
            XCTAssertEqual(values, values.sorted(), "\(kind)")
        }
    }
}

final class ProfileImportScenarioTests: XCTestCase {
    private func importing(_ json: String) throws -> FanProfile {
        try ProfileExport.profile(from: Data(json.utf8))
    }

    private let header = #""format":"com.furkansenturk.FanController.profile","version":1"#

    func testUnicodeAndEmptyNamesSurvive() throws {
        for name in ["Sessiz 🤫 Çalışma", ""] {
            let data = try ProfileExport(profile: FanProfile(name: name)).encoded()
            XCTAssertEqual(try ProfileExport.profile(from: data).name, name)
        }
    }

    func testUnknownFieldsAreIgnored() throws {
        let profile = try importing(#"""
        {\#(header),"exportedBy":"future","profile":{"id":"\#(UUID())","name":"X","defaultRule":{"automatic":{}},"rules":{}}}
        """#)
        XCTAssertEqual(profile.name, "X")
    }

    func testMissingVersionIsNotAProfile() {
        let json = #"{"format":"com.furkansenturk.FanController.profile","profile":{}}"#
        XCTAssertThrowsError(try importing(json)) { XCTAssertEqual($0 as? ProfileExport.ImportError, .notAProfile) }
    }

    func testUnknownRuleKindIsNotAProfile() {
        let json = #"""
        {\#(header),"profile":{"id":"\#(UUID())","name":"X","defaultRule":{"turbo":{}},"rules":{}}}
        """#
        XCTAssertThrowsError(try importing(json)) { XCTAssertEqual($0 as? ProfileExport.ImportError, .notAProfile) }
    }

    func testOutOfRangeFractionFromAFileStillDrivesTheFanSafely() throws {
        let profile = FanProfile(name: "Hand-edited", defaultRule: .constant(fraction: 7))
        let imported = try ProfileExport.profile(from: ProfileExport(profile: profile).encoded())
        XCTAssertEqual(imported.rule(for: 0).targetRPM(for: fan(), in: cpu(50)), 5200)
    }

    func testManyFansRoundTrip() throws {
        let rules = Dictionary(uniqueKeysWithValues: (0..<32)
            .map { ($0, FanRule.constant(fraction: Double($0) / 31)) })
        let imported = try ProfileExport
            .profile(from: ProfileExport(profile: FanProfile(name: "Rack", rules: rules)).encoded())
        XCTAssertEqual(imported.rules, rules)
    }
}

final class HIDScenarioTests: XCTestCase {
    func testNANDChannelsAndCase() {
        XCTAssertEqual(HIDTemperatures.kind(forProduct: "NAND CH10 temp"), .ssd)
        XCTAssertNil(HIDTemperatures.kind(forProduct: "nand ch0 temp"))
        XCTAssertNil(HIDTemperatures.kind(forProduct: "Gas Gauge Battery"))
    }

    func testEmptyChipNameFallsBackToCommonSensors() {
        XCTAssertEqual(SensorCatalog.definitions(forChip: ""), SensorCatalog.common)
    }
}

final class UnreadableFanRangeTests: XCTestCase {
    private let rules: [FanRule] = [
        .constant(fraction: 1),
        .constant(fraction: 0),
        .sensorBased(SensorRule(source: .hottest(.cpu), lowerCelsius: 40, upperCelsius: 80)),
        .sensorBased(SensorRule(source: .sensor("missing"), lowerCelsius: 40, upperCelsius: 80)),
    ]

    /// Missing SMC keys read as 0; driving such a fan would aim for 0 rpm and could stop it.
    func testFanWithoutARangeIsLeftToTheSMC() {
        let unreadable = [
            fan(min: 0, max: 0),
            fan(min: 1200, max: 0),
            fan(min: .nan, max: 5200),
            fan(min: 1200, max: .infinity),
            fan(min: -100, max: 5200),
            fan(min: 5000, max: 1000),
        ]
        for fan in unreadable {
            XCTAssertFalse(fan.hasKnownRange, "\(fan.minimumRPM)–\(fan.maximumRPM)")
            for rule in rules {
                XCTAssertNil(rule.targetRPM(for: fan, in: cpu(90), celsiusOverride: nil), "\(rule)")
                XCTAssertNil(rule.targetRPM(for: fan, in: cpu(90), celsiusOverride: 60), "\(rule)")
            }
        }
    }

    func testValidRangesAreStillDriven() {
        XCTAssertTrue(fan().hasKnownRange)
        XCTAssertEqual(FanRule.constant(fraction: 0.5).targetRPM(for: fan(min: 0, max: 5000), in: cpu(50)), 2500)
        XCTAssertEqual(FanRule.constant(fraction: 1).targetRPM(for: fan(min: 2000, max: 2000), in: cpu(50)), 2000)
        XCTAssertEqual(rules[3].targetRPM(for: fan(), in: cpu(50)), 5200) // missing sensor still means full speed
    }
}
