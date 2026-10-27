@testable import FanKit
import XCTest

final class FanTests: XCTestCase {
    func testPositionFollowsFanCount() {
        XCTAssertEqual(FanPosition(index: 0, count: 1), .only)
        XCTAssertEqual(FanPosition(index: 0, count: 2), .left)
        XCTAssertEqual(FanPosition(index: 1, count: 2), .right)
        XCTAssertEqual(FanPosition(index: 2, count: 3), .numbered(3))
    }

    func testLoadIsClampedToRange() {
        var fan = Fan(
            id: 0,
            position: .left,
            currentRPM: 0,
            minimumRPM: 1200,
            maximumRPM: 5800,
            targetRPM: 0,
            mode: .automatic
        )
        XCTAssertEqual(fan.load, 0) // stopped fans sit below the minimum
        fan.currentRPM = 3500
        XCTAssertEqual(fan.load, 0.5, accuracy: 0.001)
        fan.currentRPM = 6000
        XCTAssertEqual(fan.load, 1)
    }

    func testClampsToSupportedRange() {
        let fan = Fan(
            id: 0,
            position: .left,
            currentRPM: 0,
            minimumRPM: 1200,
            maximumRPM: 5800,
            targetRPM: 0,
            mode: .manual
        )
        XCTAssertEqual(fan.clamped(0), 1200)
        XCTAssertEqual(fan.clamped(3000), 3000)
        XCTAssertEqual(fan.clamped(9000), 5800)
    }
}

final class HardwareSnapshotTests: XCTestCase {
    func testAveragesPerGroup() throws {
        let snapshot = HardwareSnapshot(fans: [], sensors: [
            TemperatureSensor(definition: .init("Tp01", .performanceCore, 1), celsius: 50),
            TemperatureSensor(definition: .init("Tp09", .efficiencyCore, 1), celsius: 54),
            TemperatureSensor(definition: .init("TB0T", .battery), celsius: 30),
        ])

        XCTAssertEqual(try XCTUnwrap(snapshot.average(of: .cpu)), 52)
        XCTAssertEqual(snapshot.maximum(of: .cpu), 54)
        XCTAssertNil(snapshot.average(of: .gpu))
    }
}

final class SensorCatalogTests: XCTestCase {
    func testKeysAreUnique() {
        let keys = SensorCatalog.definitions(forChip: "Apple M1 Pro").map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testUnknownChipFallsBackToCommonSensors() {
        XCTAssertEqual(SensorCatalog.definitions(forChip: "Apple M9"), SensorCatalog.common)
    }
}

final class FanRuleTests: XCTestCase {
    private let fan = Fan(
        id: 0,
        position: .left,
        currentRPM: 2000,
        minimumRPM: 1200,
        maximumRPM: 5200,
        targetRPM: 0,
        mode: .automatic
    )

    private func snapshot(cpu: Double) -> HardwareSnapshot {
        HardwareSnapshot(fans: [fan], sensors: [
            TemperatureSensor(definition: .init("Tp01", .performanceCore, 1), celsius: cpu),
        ])
    }

    func testAutomaticLeavesSpeedToSMC() {
        XCTAssertNil(FanRule.automatic.targetRPM(for: fan, in: snapshot(cpu: 60)))
    }

    func testConstantMapsFractionToRange() {
        XCTAssertEqual(FanRule.constant(fraction: 0).targetRPM(for: fan, in: snapshot(cpu: 60)), 1200)
        XCTAssertEqual(FanRule.constant(fraction: 0.5).targetRPM(for: fan, in: snapshot(cpu: 60)), 3200)
        XCTAssertEqual(FanRule.constant(fraction: 1).targetRPM(for: fan, in: snapshot(cpu: 60)), 5200)
    }

    func testSensorRuleIsLinearBetweenTemperatures() {
        let rule = FanRule.sensorBased(SensorRule(source: .hottest(.cpu), lowerCelsius: 40, upperCelsius: 80))
        XCTAssertEqual(rule.targetRPM(for: fan, in: snapshot(cpu: 30)), 1200)
        XCTAssertEqual(rule.targetRPM(for: fan, in: snapshot(cpu: 60)), 3200)
        XCTAssertEqual(rule.targetRPM(for: fan, in: snapshot(cpu: 95)), 5200)
    }

    func testMissingSensorRunsAtMaximum() {
        let rule = FanRule.sensorBased(SensorRule(source: .sensor("TB0T"), lowerCelsius: 40, upperCelsius: 80))
        XCTAssertEqual(rule.targetRPM(for: fan, in: snapshot(cpu: 30)), 5200)
    }
}

final class FanProfileTests: XCTestCase {
    func testBuiltInProfiles() {
        XCTAssertEqual(FanProfile.automatic.rule(for: 0), .automatic)
        XCTAssertEqual(FanProfile.fullSpeed.rule(for: 1), .constant(fraction: 1))
        XCTAssertTrue(FanProfile.fullSpeed.isBuiltIn)
        XCTAssertFalse(FanProfile(name: "Quiet").isBuiltIn)
    }

    func testOnlyCustomAndOwnProfilesAreEditable() {
        XCTAssertFalse(FanProfile.automatic.isEditable)
        XCTAssertFalse(FanProfile.fullSpeed.isEditable)
        XCTAssertTrue(FanProfile.custom.isEditable)
        XCTAssertTrue(FanProfile.custom.isBuiltIn)
        XCTAssertTrue(FanProfile(name: "Quiet").isEditable)
    }

    func testPerFanRuleOverridesDefault() {
        let profile = FanProfile(name: "Quiet", rules: [1: .constant(fraction: 0.2)])
        XCTAssertEqual(profile.rule(for: 0), .automatic)
        XCTAssertEqual(profile.rule(for: 1), .constant(fraction: 0.2))
    }

    func testRoundTripsThroughJSON() throws {
        let profile = FanProfile(name: "Gaming", rules: [
            0: .sensorBased(SensorRule(source: .average(.gpu), lowerCelsius: 45, upperCelsius: 75)),
            1: .constant(fraction: 0.6),
        ])
        let data = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(FanProfile.self, from: data), profile)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("gpu.average"))
    }

    func testTemperatureSourceRawValues() {
        for source in [TemperatureSource.hottest(.cpu), .average(.gpu), .sensor("Tp01")] {
            XCTAssertEqual(TemperatureSource(rawValue: source.rawValue), source)
        }
        XCTAssertNil(TemperatureSource(rawValue: "none"))
    }
}

final class HIDTemperaturesTests: XCTestCase {
    func testRecognizesKnownProducts() {
        XCTAssertEqual(HIDTemperatures.kind(forProduct: "NAND CH0 temp"), .ssd)
        XCTAssertEqual(HIDTemperatures.kind(forProduct: "NAND CH1 temp"), .ssd)
        XCTAssertEqual(HIDTemperatures.kind(forProduct: "gas gauge battery"), .batteryGasGauge)
        XCTAssertEqual(HIDTemperatures.kind(forProduct: "PMU tdie10"), .powerManager)
        XCTAssertNil(HIDTemperatures.kind(forProduct: "PMU tcal"))
        XCTAssertNil(HIDTemperatures.kind(forProduct: "PMU tdev1"))
    }
}

final class SensorRuleExtensionTests: XCTestCase {
    func testFollowsTheHottestSource() {
        let snapshot = HardwareSnapshot(fans: [], sensors: [
            TemperatureSensor(definition: .init("Tp01", .performanceCore, 1), celsius: 60),
            TemperatureSensor(definition: .init("Tg05", .gpuCluster, 1), celsius: 72),
        ])
        let rule = SensorRule(
            source: .average(.cpu),
            extraSources: [.average(.gpu)],
            lowerCelsius: 40,
            upperCelsius: 80
        )
        XCTAssertEqual(rule.celsius(in: snapshot), 72)
    }

    func testHysteresisHoldsUntilTheTemperatureFallsFarEnough() {
        XCTAssertEqual(Hysteresis.effective(current: 70, previous: 65, band: 3), 70) // rising: follow
        XCTAssertEqual(Hysteresis.effective(current: 68, previous: 70, band: 3), 70) // small drop: hold
        XCTAssertEqual(Hysteresis.effective(current: 67, previous: 70, band: 3), 67) // dropped by the band: follow
        XCTAssertEqual(Hysteresis.effective(current: 50, previous: nil, band: 3), 50)
        XCTAssertEqual(Hysteresis.effective(current: 68, previous: 70, band: 0), 68)
    }

    func testDecodesRulesSavedBeforeTheNewFields() throws {
        let json = #"{"source":"cpu.hottest","lowerCelsius":50,"upperCelsius":80}"#
        let rule = try JSONDecoder().decode(SensorRule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.extraSources, [])
        XCTAssertEqual(rule.hysteresisCelsius, SensorRule.defaultHysteresis)
    }
}

final class ProfileExportTests: XCTestCase {
    func testRoundTripsWithANewID() throws {
        let profile = FanProfile(name: "Quiet", rules: [0: .constant(fraction: 0.3)])
        let imported = try ProfileExport.profile(from: ProfileExport(profile: profile).encoded())
        XCTAssertEqual(imported.name, "Quiet")
        XCTAssertEqual(imported.rules, profile.rules)
        XCTAssertNotEqual(imported.id, profile.id)
    }

    func testRejectsOtherJSON() {
        XCTAssertThrowsError(try ProfileExport.profile(from: Data(#"{"name":"x"}"#.utf8))) { error in
            XCTAssertEqual(error as? ProfileExport.ImportError, .notAProfile)
        }
    }

    func testRejectsNewerVersions() throws {
        var json = String(decoding: try ProfileExport(profile: FanProfile(name: "x")).encoded(), as: UTF8.self)
        json = json.replacingOccurrences(of: #""version" : 1"#, with: #""version" : 99"#)
        XCTAssertThrowsError(try ProfileExport.profile(from: Data(json.utf8))) { error in
            XCTAssertEqual(error as? ProfileExport.ImportError, .newerVersion(99))
        }
    }
}

final class TemperatureAlertTests: XCTestCase {
    private let alert = TemperatureAlert(source: .hottest(.cpu), thresholdCelsius: 90)

    func testFiresOnceThenRearmsAfterCooling() {
        XCTAssertNil(alert.transition(celsius: 85, armed: true))
        XCTAssertEqual(alert.transition(celsius: 91, armed: true), .fire)
        XCTAssertNil(alert.transition(celsius: 92, armed: false)) // still hot: no repeat
        XCTAssertNil(alert.transition(celsius: 87, armed: false)) // hovering: no repeat
        XCTAssertEqual(alert.transition(celsius: 85, armed: false), .rearm)
    }
}

final class AutomationTests: XCTestCase {
    private let quiet = UUID()
    private let full = UUID()

    private var rules: [AutomationRule] {
        [
            AutomationRule(
                condition: .appRunning(bundleID: "com.apple.FinalCut", name: "Final Cut Pro"),
                profileID: full
            ),
            AutomationRule(condition: .onBattery, profileID: quiet),
        ]
    }

    func testFirstMatchingRuleWins() {
        let context = AutomationContext(isOnBattery: true, runningBundleIDs: ["com.apple.FinalCut"])
        XCTAssertEqual(
            Automation.matchingRule(in: rules, context: context, existingProfiles: [quiet, full])?.profileID,
            full
        )
    }

    func testFallsThroughToLaterRules() {
        let context = AutomationContext(isOnBattery: true, runningBundleIDs: [])
        XCTAssertEqual(
            Automation.matchingRule(in: rules, context: context, existingProfiles: [quiet, full])?.profileID,
            quiet
        )
    }

    func testSkipsDisabledRulesAndDeletedProfiles() {
        var rules = rules
        rules[1].isEnabled = false
        let context = AutomationContext(isOnBattery: true, runningBundleIDs: ["com.apple.FinalCut"])
        XCTAssertNil(Automation.matchingRule(in: rules, context: context, existingProfiles: [quiet]))
    }

    func testRulesRoundTripThroughJSON() throws {
        let original = rules
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode([AutomationRule].self, from: data), original)
    }
}

final class ThermalLimitsTests: XCTestCase {
    func testSeverityRisesFromWarmToCritical() {
        let limits = SensorKind.performanceCore.thermalLimits
        XCTAssertEqual(limits.severity(at: 50), 0)
        XCTAssertEqual(limits.severity(at: 70), 0)
        XCTAssertEqual(limits.severity(at: 82.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(limits.severity(at: 95), 1)
        XCTAssertEqual(limits.severity(at: 105), 1)
        XCTAssertTrue(limits.isCritical(95))
        XCTAssertFalse(limits.isCritical(94.9))
    }

    func testEveryKindHasSensibleLimits() {
        for kind in SensorKind.allCases {
            XCTAssertLessThan(kind.thermalLimits.warmCelsius, kind.thermalLimits.criticalCelsius, "\(kind)")
        }
    }
}
