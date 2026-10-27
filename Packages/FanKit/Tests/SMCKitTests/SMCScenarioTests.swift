@testable import SMCKit
import XCTest

/// Extreme and malformed values at the boundary with the hardware.
final class SMCDecodingExtremesTests: XCTestCase {
    private func value(_ type: SMCDataType, _ bytes: [UInt8]) -> SMCValue {
        SMCValue(key: "TEST", dataType: type, bytes: bytes)
    }

    func testFixedPointLimits() {
        XCTAssertEqual(value(.sp78, [0x80, 0x00]).doubleValue, -128)
        XCTAssertEqual(value(.sp78, [0x7F, 0xFF]).doubleValue, 127.99609375)
        XCTAssertEqual(value(.fpe2, [0xFF, 0xFF]).doubleValue, 16383.75)
        XCTAssertEqual(value(.fp88, [0xFF, 0xFF]).doubleValue, 255.99609375)
    }

    func testIntegerLimits() {
        XCTAssertEqual(value(.ui16, [0xFF, 0xFF]).doubleValue, 65535)
        XCTAssertEqual(value(.ui32, [0xFF, 0xFF, 0xFF, 0xFF]).doubleValue, 4_294_967_295)
        XCTAssertEqual(value(.si16, [0x80, 0x00]).doubleValue, -32768)
        XCTAssertEqual(value(.si8, [0x80]).doubleValue, -128)
    }

    func testFloatSpecialValuesPassThrough() throws {
        XCTAssertTrue(try XCTUnwrap(value(.flt, [0x00, 0x00, 0xC0, 0x7F]).doubleValue).isNaN)
        XCTAssertEqual(value(.flt, [0x00, 0x00, 0x80, 0x7F]).doubleValue, .infinity)
        XCTAssertEqual(value(.flt, [0x00, 0x00, 0x80, 0xFF]).doubleValue, -.infinity)
    }

    func testTooManyBytesAreRejected() {
        XCTAssertNil(value(.flt, [0, 0, 0, 0, 0]).doubleValue)
        XCTAssertNil(value(.ui8, [1, 2]).doubleValue)
        XCTAssertNil(value(.sp78, [1, 2, 3]).doubleValue)
    }
}

final class SMCEncodingExtremesTests: XCTestCase {
    /// A NaN or infinite speed must never reach the SMC, and must not trap the root helper.
    func testNonFiniteValuesCannotBeEncoded() {
        for type in [SMCDataType.flt, .fpe2, .ui8, .flag] {
            for value in [Double.nan, .infinity, -.infinity] {
                XCTAssertNil(type.encode(value), "\(type) \(value)")
            }
        }
    }

    func testFloatOverflowCannotBeEncoded() {
        XCTAssertNil(SMCDataType.flt.encode(1e40))
        XCTAssertNotNil(SMCDataType.flt.encode(Double(Float.greatestFiniteMagnitude)))
    }

    func testValuesBeyondIntRangeAreClamped() {
        XCTAssertEqual(SMCDataType.fpe2.encode(1e300), [0xFF, 0xFF])
        XCTAssertEqual(SMCDataType.ui8.encode(-1e300), [0])
    }

    func testRoundingAtTheResolutionOfEachType() throws {
        XCTAssertEqual(
            try SMCValue(key: "TEST", dataType: .fpe2, bytes: XCTUnwrap(SMCDataType.fpe2.encode(2400.1))).doubleValue,
            2400
        )
        XCTAssertEqual(SMCDataType.fpe2.encode(0.125), [0x00, 0x01]) // halfway rounds away from zero
        XCTAssertEqual(SMCDataType.ui8.encode(255.5), [255])
        XCTAssertEqual(SMCDataType.ui8.encode(-0.4), [0])
    }

    func testNegativeZeroEncodesAsZero() {
        XCTAssertEqual(SMCDataType.fpe2.encode(-0.0), [0x00, 0x00])
    }
}

final class FourCCScenarioTests: XCTestCase {
    func testRoundTripsKeysWithSymbolsAndSpaces() {
        for name in ["#KEY", "flt ", "ch8*", "TB0T", "Tp0b"] {
            XCTAssertEqual(SMCKey(name).name, name)
        }
    }

    func testDecodingArbitraryCodesNeverCrashes() {
        XCTAssertEqual(SMCKey(code: 0).name, "\0\0\0\0")
        XCTAssertFalse(SMCKey(code: 0xFFFF_FFFF).name.isEmpty)
    }

    func testValidatesFanIndices() {
        XCTAssertTrue(SMCKey.isValidFanIndex(0))
        XCTAssertTrue(SMCKey.isValidFanIndex(9))
        XCTAssertFalse(SMCKey.isValidFanIndex(10)) // "F10Ac" is five characters
        XCTAssertFalse(SMCKey.isValidFanIndex(-1))
    }
}

/// The checks the privileged helper applies to every request before it writes to the SMC.
final class FanLimitsTests: XCTestCase {
    func testFanIndicesFromAnUntrustedCount() {
        XCTAssertEqual(FanLimits.indices(count: 2), 0..<2)
        XCTAssertEqual(FanLimits.indices(count: 1.9), 0..<1)
        XCTAssertEqual(FanLimits.indices(count: 12), 0..<10) // beyond F9Ac there are no keys
        for count in [nil, 0, 0.5, -1, .nan, .infinity] as [Double?] {
            XCTAssertEqual(FanLimits.indices(count: count), 0..<0, "\(String(describing: count))")
        }
    }

    func testEveryIndexItReturnsHasKeys() {
        for fan in FanLimits.indices(count: 255) {
            XCTAssertTrue(SMCKey.isValidFanIndex(fan))
            XCTAssertEqual(SMCKey.fanTarget(fan).name.count, 4)
        }
    }

    func testTargetIsClampedToTheReportedRange() {
        XCTAssertEqual(FanLimits.target(rpm: 3000, minimum: 1200, maximum: 5200), 3000)
        XCTAssertEqual(FanLimits.target(rpm: 0, minimum: 1200, maximum: 5200), 1200)
        XCTAssertEqual(FanLimits.target(rpm: 1e300, minimum: 1200, maximum: 5200), 5200)
        XCTAssertEqual(FanLimits.target(rpm: 2500, minimum: 0, maximum: 5000), 2500)
        XCTAssertEqual(FanLimits.target(rpm: 9000, minimum: 2000, maximum: 2000), 2000)
    }

    /// Before, an unreadable range let the requested speed through unclamped.
    func testRefusesWhenTheRangeCantBeRead() {
        let ranges: [(Double?, Double?)] = [
            (nil, 5200), (1200, nil), (nil, nil), (0, 0), (1200, 0), (5000, 1000), (-100, 5200), (.nan, 5200), (
                1200,
                .infinity
            ),
        ]
        for (minimum, maximum) in ranges {
            XCTAssertNil(
                FanLimits.target(rpm: 3000, minimum: minimum, maximum: maximum),
                "\(String(describing: minimum))–\(String(describing: maximum))"
            )
        }
    }

    func testRefusesSpeedsThatArentNumbers() {
        for rpm in [Double.nan, .infinity, -.infinity] {
            XCTAssertNil(FanLimits.target(rpm: rpm, minimum: 1200, maximum: 5200))
        }
    }
}
