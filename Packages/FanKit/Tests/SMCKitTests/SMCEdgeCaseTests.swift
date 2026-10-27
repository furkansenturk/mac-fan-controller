@testable import SMCKit
import XCTest

final class SMCKeyNamingTests: XCTestCase {
    func testWellKnownKeys() {
        XCTAssertEqual(SMCKey.keyCount.name, "#KEY")
        XCTAssertEqual(SMCKey.fanCount.name, "FNum")
        XCTAssertEqual(SMCKey.fanMinimum(0).name, "F0Mn")
        XCTAssertEqual(SMCKey.fanMaximum(1).name, "F1Mx")
    }

    func testCodeAndLiteralAgree() {
        XCTAssertEqual(SMCKey(code: 0x464E_756D), "FNum")
        XCTAssertEqual(SMCKey("Tp01").description, "Tp01")
    }

    func testDataTypeNames() {
        XCTAssertEqual(SMCDataType.flt.name, "flt ")
        XCTAssertEqual(SMCDataType.sp78.description, "sp78")
        XCTAssertEqual(SMCDataType(code: SMCDataType.ui16.code), .ui16)
    }
}

final class SMCValueEdgeCaseTests: XCTestCase {
    private func value(_ type: SMCDataType, _ bytes: [UInt8]) -> SMCValue {
        SMCValue(key: "TEST", dataType: type, bytes: bytes)
    }

    func testDecodesRemainingNumericTypes() {
        XCTAssertEqual(value(.fp88, [0x34, 0x80]).doubleValue, 52.5)
        XCTAssertEqual(value(.si8, [0xFE]).doubleValue, -2)
        XCTAssertEqual(value(.si16, [0xFF, 0xFE]).doubleValue, -2)
        XCTAssertEqual(value(.flag, [1]).doubleValue, 1)
    }

    func testUnknownTypesAndShortDataAreNotNumbers() {
        XCTAssertNil(value(SMCDataType("ch8*"), [0x41, 0x42]).doubleValue)
        XCTAssertNil(value(.ui32, [0, 1]).doubleValue)
        XCTAssertNil(value(.ui8, []).doubleValue)
    }

    func testEncodesFloatLittleEndian() {
        XCTAssertEqual(SMCDataType.flt.encode(52.5), [0x00, 0x00, 0x52, 0x42])
    }

    func testEncodingClampsToTheTypesRange() {
        XCTAssertEqual(SMCDataType.fpe2.encode(-10), [0x00, 0x00])
        XCTAssertEqual(SMCDataType.fpe2.encode(100_000), [0xFF, 0xFF])
        XCTAssertEqual(SMCDataType.ui8.encode(300), [255])
        XCTAssertEqual(SMCDataType.ui8.encode(-1), [0])
        XCTAssertEqual(SMCDataType.flag.encode(0.6), [1])
    }

    func testReadOnlyTypesCannotBeEncoded() {
        for type in [SMCDataType.fp88, .ui16, .ui32, .si8, .si16] {
            XCTAssertNil(type.encode(1), "\(type)")
        }
    }
}

final class SMCErrorTests: XCTestCase {
    func testDescriptions() {
        XCTAssertEqual(SMCError.keyNotFound("F0Ac").description, "SMC key F0Ac not found")
        XCTAssertEqual(
            SMCError.sizeMismatch("F0Tg", expected: 4, actual: 2).description,
            "SMC key F0Tg expects 4 bytes, got 2"
        )
        XCTAssertEqual(
            SMCError.unsupportedType("TEST", .sp78).description,
            "Cannot encode a value for SMC key TEST of type sp78"
        )
        XCTAssertEqual(SMCError.smc(code: 0x84).description, "SMC returned error 0x84")
        XCTAssertEqual(SMCError.ioKit(kern_return_t(bitPattern: 0xE000_02C2)).description, "IOKit error 0xe00002c2")
    }
}
