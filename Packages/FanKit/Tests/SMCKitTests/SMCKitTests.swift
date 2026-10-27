@testable import SMCKit
import XCTest

final class SMCParamStructTests: XCTestCase {
    /// The kernel expects the exact C layout of `SMCParamStruct`.
    func testLayoutMatchesKernelStruct() {
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.stride, 80)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.key), 0)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.version), 4)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.pLimitData), 12)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.keyInfo), 28)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.result), 40)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.status), 41)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.data8), 42)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.data32), 44)
        XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.bytes), 48)
    }
}

final class SMCKeyTests: XCTestCase {
    func testRoundTripsName() {
        let key: SMCKey = "F0Ac"
        XCTAssertEqual(key.code, 0x4630_4163)
        XCTAssertEqual(key.name, "F0Ac")
    }

    func testFanKeys() {
        XCTAssertEqual(SMCKey.fanActual(1).name, "F1Ac")
        XCTAssertEqual(SMCKey.fanTarget(0).name, "F0Tg")
        XCTAssertEqual(SMCKey.fanMode(1).name, "F1Md")
    }
}

final class SMCValueTests: XCTestCase {
    private func value(_ type: SMCDataType, _ bytes: [UInt8]) -> SMCValue {
        SMCValue(key: "TEST", dataType: type, bytes: bytes)
    }

    func testDecodesLittleEndianFloat() {
        // 52.5 as IEEE 754 single precision is 0x42520000.
        XCTAssertEqual(value(.flt, [0x00, 0x00, 0x52, 0x42]).doubleValue, 52.5)
    }

    func testDecodesFixedPointTypes() {
        XCTAssertEqual(value(.fpe2, [0x23, 0xE8]).doubleValue, 2298) // 9192 / 4
        XCTAssertEqual(value(.sp78, [0x34, 0x80]).doubleValue, 52.5)
        XCTAssertEqual(value(.sp78, [0xFF, 0x00]).doubleValue, -1)
    }

    func testDecodesIntegers() {
        XCTAssertEqual(value(.ui8, [2]).doubleValue, 2)
        XCTAssertEqual(value(.ui16, [0x01, 0x00]).doubleValue, 256)
        XCTAssertEqual(value(.ui32, [0, 0, 0x0A, 0x2B]).doubleValue, 2603)
    }

    func testRejectsUnexpectedSize() {
        XCTAssertNil(value(.flt, [0, 0]).doubleValue)
    }

    func testEncodeRoundTrips() throws {
        for type in [SMCDataType.flt, .fpe2] {
            let bytes = try XCTUnwrap(type.encode(2400))
            XCTAssertEqual(value(type, bytes).doubleValue, 2400)
        }
        XCTAssertEqual(SMCDataType.ui8.encode(1), [1])
        XCTAssertNil(SMCDataType.sp78.encode(1))
    }
}
