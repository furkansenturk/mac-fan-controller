@testable import FanKit
import XCTest

final class FanRangeTests: XCTestCase {
    private let fan = Fan(
        id: 0,
        position: .left,
        currentRPM: 0,
        minimumRPM: 1200,
        maximumRPM: 5200,
        targetRPM: 0,
        mode: .automatic
    )

    func testRPMAndFractionAreInverse() {
        XCTAssertEqual(fan.rpm(at: 0.25), 2200)
        XCTAssertEqual(fan.fraction(of: 2200), 0.25)
    }

    func testFractionsOutsideTheRangeAreClamped() {
        XCTAssertEqual(fan.rpm(at: -1), 1200)
        XCTAssertEqual(fan.rpm(at: 2), 5200)
        XCTAssertEqual(fan.fraction(of: 100), 0)
        XCTAssertEqual(fan.fraction(of: 9000), 1)
    }

    func testFanWithoutARangeReportsNoLoad() {
        let fixed = Fan(
            id: 0,
            position: .only,
            currentRPM: 2000,
            minimumRPM: 2000,
            maximumRPM: 2000,
            targetRPM: 0,
            mode: .automatic
        )
        XCTAssertEqual(fixed.load, 0)
        XCTAssertEqual(fixed.fraction(of: 2000), 0)
    }

    func testPositionsBeyondTwoFansAreNumbered() {
        XCTAssertEqual(FanPosition(index: 0, count: 3), .numbered(1))
        XCTAssertEqual(FanPosition(index: 0, count: 0), .numbered(1))
    }
}

final class SensorGroupingTests: XCTestCase {
    func testEveryKindBelongsToTheExpectedGroup() {
        let expected: [SensorKind: SensorGroup] = [
            .efficiencyCore: .cpu, .performanceCore: .cpu, .gpuCluster: .gpu, .memory: .memory, .ssd: .disks,
        ]
        for kind in SensorKind.allCases {
            XCTAssertEqual(kind.group, expected[kind] ?? .other, "\(kind)")
        }
    }

    func testOnlyHomogeneousGroupsHaveAnAverage() {
        XCTAssertEqual(SensorGroup.allCases.filter(\.hasAverage), [.cpu, .gpu, .memory])
    }

    func testEmptySnapshotHasNoSummaries() {
        let snapshot = HardwareSnapshot(fans: [], sensors: [])
        for group in SensorGroup.allCases {
            XCTAssertNil(snapshot.average(of: group))
            XCTAssertNil(snapshot.maximum(of: group))
        }
    }

    func testM1MaxSharesTheM1ProCatalog() {
        XCTAssertEqual(
            SensorCatalog.definitions(forChip: "Apple M1 Max"),
            SensorCatalog.definitions(forChip: "Apple M1 Pro")
        )
    }

    func testChipSpecificKeysComeBeforeCommonOnes() {
        let definitions = SensorCatalog.definitions(forChip: "Apple M1 Pro")
        XCTAssertEqual(Array(definitions.suffix(SensorCatalog.common.count)), SensorCatalog.common)
        XCTAssertEqual(definitions.first { $0.key == "Tp09" }?.kind, .efficiencyCore)
    }

    func testNumberedKindsHaveDistinctNumbers() {
        let definitions = SensorCatalog.definitions(forChip: "Apple M1 Pro")
        for kind in SensorKind.allCases {
            let numbers = definitions.filter { $0.kind == kind }.compactMap(\.number)
            XCTAssertEqual(Set(numbers).count, numbers.count, "\(kind)")
        }
    }
}

final class TemperatureSourceTests: XCTestCase {
    private let snapshot = HardwareSnapshot(fans: [], sensors: [
        TemperatureSensor(definition: .init("Tm02", .memory, 1), celsius: 40),
        TemperatureSensor(definition: .init("Tm06", .memory, 2), celsius: 50),
        TemperatureSensor(id: "hid.ssd", kind: .ssd, celsius: 38),
    ])

    /// The app offers group summaries for CPU, GPU and memory; every one must survive being saved.
    func testEverySummaryRoundTripsThroughItsRawValue() {
        for group in SensorGroup.allCases {
            for source in [TemperatureSource.hottest(group), .average(group)] {
                XCTAssertEqual(TemperatureSource(rawValue: source.rawValue), source, source.rawValue)
            }
        }
    }

    func testProfileFollowingMemoryRoundTripsThroughJSON() throws {
        let profile = FanProfile(name: "Memory", rules: [
            0: .sensorBased(SensorRule(
                source: .hottest(.memory),
                extraSources: [.average(.memory)],
                lowerCelsius: 40,
                upperCelsius: 70
            )),
        ])
        let data = try JSONEncoder().encode([profile])
        XCTAssertEqual(try JSONDecoder().decode([FanProfile].self, from: data), [profile])
    }

    func testSensorKeysMayContainDots() {
        XCTAssertEqual(TemperatureSource(rawValue: "sensor.hid.ssd"), .sensor("hid.ssd"))
        XCTAssertEqual(TemperatureSource.sensor("hid.ssd").celsius(in: snapshot), 38)
    }

    func testRejectsMalformedRawValues() {
        for raw in ["", "cpu", "cpu.median", "fans.hottest", ".hottest"] {
            XCTAssertNil(TemperatureSource(rawValue: raw), raw)
        }
    }

    func testDecodingAnUnknownSourceThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode([TemperatureSource].self, from: Data(#"["cpu.median"]"#.utf8)))
    }

    func testReadsFromTheSnapshot() {
        XCTAssertEqual(TemperatureSource.hottest(.memory).celsius(in: snapshot), 50)
        XCTAssertEqual(TemperatureSource.average(.memory).celsius(in: snapshot), 45)
        XCTAssertNil(TemperatureSource.sensor("Tp01").celsius(in: snapshot))
        XCTAssertNil(TemperatureSource.hottest(.cpu).celsius(in: snapshot))
    }
}

final class SensorRuleEdgeCaseTests: XCTestCase {
    private let fan = Fan(
        id: 0,
        position: .left,
        currentRPM: 2000,
        minimumRPM: 1200,
        maximumRPM: 5200,
        targetRPM: 0,
        mode: .automatic
    )

    func testCollapsedRangeSwitchesAtTheUpperTemperature() {
        let rule = SensorRule(source: .hottest(.cpu), lowerCelsius: 60, upperCelsius: 60)
        XCTAssertEqual(rule.fraction(at: 59.9), 0)
        XCTAssertEqual(rule.fraction(at: 60), 1)
    }

    func testInvertedRangeDoesNotProduceNegativeSpeeds() {
        let rule = SensorRule(source: .hottest(.cpu), lowerCelsius: 80, upperCelsius: 40)
        XCTAssertEqual(rule.fraction(at: 20), 0)
        XCTAssertEqual(rule.fraction(at: 90), 1)
    }

    func testOverrideReplacesTheMeasuredTemperature() {
        let rule = FanRule.sensorBased(SensorRule(source: .hottest(.cpu), lowerCelsius: 40, upperCelsius: 80))
        let cold = HardwareSnapshot(fans: [fan], sensors: [
            TemperatureSensor(definition: .init("Tp01", .performanceCore, 1), celsius: 30),
        ])
        XCTAssertEqual(rule.targetRPM(for: fan, in: cold, celsiusOverride: 60), 3200)
        // An override still counts as a reading, so a missing sensor doesn't force full speed.
        XCTAssertEqual(
            rule.targetRPM(for: fan, in: HardwareSnapshot(fans: [fan], sensors: []), celsiusOverride: 40),
            1200
        )
    }

    func testRuleWithoutAnyReadingHasNoTemperature() {
        let rule = SensorRule(
            source: .sensor("Tp01"),
            extraSources: [.average(.gpu)],
            lowerCelsius: 40,
            upperCelsius: 80
        )
        XCTAssertEqual(rule.sources, [.sensor("Tp01"), .average(.gpu)])
        XCTAssertNil(rule.celsius(in: HardwareSnapshot(fans: [], sensors: [])))
    }

    func testHysteresisEdgeCases() {
        XCTAssertEqual(Hysteresis.effective(current: 70, previous: 70, band: 3), 70)
        XCTAssertEqual(Hysteresis.effective(current: 68, previous: 70, band: -3), 68)
    }

    func testEveryRuleKindRoundTripsThroughJSON() throws {
        let rules: [FanRule] = [.automatic, .constant(fraction: 0.4), .sensorBased(.default)]
        XCTAssertEqual(try JSONDecoder().decode([FanRule].self, from: JSONEncoder().encode(rules)), rules)
    }
}

final class FanProfileEdgeCaseTests: XCTestCase {
    func testDefaultRuleCoversFansWithoutTheirOwnRule() {
        let profile = FanProfile(name: "Warm", defaultRule: .constant(fraction: 0.3), rules: [1: .automatic])
        XCTAssertEqual(profile.rule(for: 0), .constant(fraction: 0.3))
        XCTAssertEqual(profile.rule(for: 1), .automatic)
        XCTAssertEqual(profile.rule(for: 7), .constant(fraction: 0.3))
    }

    func testBuiltInProfilesHaveFixedDistinctIDs() {
        XCTAssertEqual(Set(FanProfile.builtIn.map(\.id)).count, 3)
        XCTAssertEqual(FanProfile.automatic.id.uuidString, "00000000-0000-0000-0000-00000000A0A0")
        XCTAssertFalse(FanProfile(id: UUID(), name: "Automatic").isBuiltIn) // identified by ID, not name
    }
}

final class AutomationEdgeCaseTests: XCTestCase {
    private let profile = UUID()

    func testPowerAdapterRuleMatchesOnlyWhenPluggedIn() {
        let rules = [AutomationRule(condition: .onPowerAdapter, profileID: profile)]
        XCTAssertNotNil(Automation.matchingRule(
            in: rules,
            context: .init(isOnBattery: false, runningBundleIDs: []),
            existingProfiles: [profile]
        ))
        XCTAssertNil(Automation.matchingRule(
            in: rules,
            context: .init(isOnBattery: true, runningBundleIDs: []),
            existingProfiles: [profile]
        ))
    }

    func testAppRuleNeedsTheAppToBeRunning() {
        let rules = [AutomationRule(
            condition: .appRunning(bundleID: "com.example.Game", name: "Game"),
            profileID: profile
        )]
        let context = AutomationContext(isOnBattery: false, runningBundleIDs: ["com.example.Other"])
        XCTAssertNil(Automation.matchingRule(in: rules, context: context, existingProfiles: [profile]))
    }

    func testNoRulesMatchNothing() {
        XCTAssertNil(Automation.matchingRule(
            in: [],
            context: .init(isOnBattery: true, runningBundleIDs: []),
            existingProfiles: [profile]
        ))
    }
}

final class TemperatureAlertEdgeCaseTests: XCTestCase {
    private let alert = TemperatureAlert(source: .hottest(.cpu), thresholdCelsius: 90)

    func testFiresOnlyAboveTheThreshold() {
        XCTAssertNil(alert.transition(celsius: 90, armed: true))
        XCTAssertEqual(alert.transition(celsius: 90.1, armed: true), .fire)
    }

    func testRearmsExactlyAtTheRearmTemperature() {
        XCTAssertNil(alert.transition(celsius: 85.1, armed: false))
        XCTAssertEqual(alert.transition(celsius: 85, armed: false), .rearm)
    }

    func testArmedAlertDoesNotRearmAgain() {
        XCTAssertNil(alert.transition(celsius: 40, armed: true))
    }

    func testRoundTripsThroughJSON() throws {
        let alerts = [alert, TemperatureAlert(source: .sensor("TB0T"), thresholdCelsius: 40, isEnabled: false)]
        XCTAssertEqual(try JSONDecoder().decode([TemperatureAlert].self, from: JSONEncoder().encode(alerts)), alerts)
    }
}

final class ThermalLimitsEdgeCaseTests: XCTestCase {
    func testCollapsedLimitsJumpStraightToCritical() {
        let limits = ThermalLimits(warmCelsius: 60, criticalCelsius: 60)
        XCTAssertEqual(limits.severity(at: 59), 0)
        XCTAssertEqual(limits.severity(at: 60), 1)
    }

    func testGroupLimitsFollowTheirTypicalSensor() {
        XCTAssertEqual(SensorGroup.cpu.thermalLimits, SensorKind.performanceCore.thermalLimits)
        XCTAssertEqual(SensorGroup.gpu.thermalLimits, SensorKind.gpuCluster.thermalLimits)
        XCTAssertEqual(SensorGroup.memory.thermalLimits, SensorKind.memory.thermalLimits)
        XCTAssertEqual(SensorGroup.disks.thermalLimits, SensorKind.ssd.thermalLimits)
        XCTAssertNil(SensorGroup.other.thermalLimits)
    }
}

final class ProfileExportEdgeCaseTests: XCTestCase {
    func testRejectsAnotherFormatAndInvalidJSON() throws {
        let otherFormat = try String(decoding: ProfileExport(profile: FanProfile(name: "x")).encoded(), as: UTF8.self)
            .replacingOccurrences(of: ProfileExport.formatIdentifier, with: "com.example.other")
        for data in [Data(otherFormat.utf8), Data("not json".utf8), Data()] {
            XCTAssertThrowsError(try ProfileExport.profile(from: data)) { error in
                XCTAssertEqual(error as? ProfileExport.ImportError, .notAProfile)
            }
        }
    }

    func testAcceptsOlderVersions() throws {
        let json = try String(decoding: ProfileExport(profile: FanProfile(name: "Old")).encoded(), as: UTF8.self)
            .replacingOccurrences(of: #""version" : 1"#, with: #""version" : 0"#)
        XCTAssertEqual(try ProfileExport.profile(from: Data(json.utf8)).name, "Old")
    }

    func testKeepsTheDefaultRule() throws {
        let profile = FanProfile(name: "Loud", defaultRule: .constant(fraction: 0.8))
        XCTAssertEqual(
            try ProfileExport.profile(from: ProfileExport(profile: profile).encoded()).defaultRule,
            .constant(fraction: 0.8)
        )
    }

    func testImportingAnExportedBuiltInMakesItCustom() throws {
        let imported = try ProfileExport.profile(from: ProfileExport(profile: .fullSpeed).encoded())
        XCTAssertFalse(imported.isBuiltIn)
        XCTAssertTrue(imported.isEditable)
    }
}

final class HIDProductNameTests: XCTestCase {
    func testRequiresTheFullProductName() {
        XCTAssertNil(HIDTemperatures.kind(forProduct: "NAND CH0"))
        XCTAssertNil(HIDTemperatures.kind(forProduct: "gas gauge battery 2"))
        XCTAssertNil(HIDTemperatures.kind(forProduct: ""))
        XCTAssertEqual(HIDTemperatures.kind(forProduct: "PMU tdie1"), .powerManager)
    }
}
