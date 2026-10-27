/// The four-character type tag the SMC reports for every key, e.g. `flt ` or `sp78`.
public struct SMCDataType: Hashable, Sendable, CustomStringConvertible {
    public let code: UInt32

    public init(code: UInt32) {
        self.code = code
    }

    init(_ name: String) {
        code = FourCC.code(string: name)
    }

    public var name: String { FourCC.string(from: code) }

    public var description: String { name }

    /// 32-bit IEEE float, little-endian. Used by Apple Silicon for temperatures and fan speeds.
    public static let flt = SMCDataType("flt ")
    /// Unsigned fixed point, 14 integer bits and 2 fraction bits, big-endian. Intel fan speeds.
    public static let fpe2 = SMCDataType("fpe2")
    /// Signed fixed point, 8 integer bits and 8 fraction bits, big-endian. Intel temperatures.
    public static let sp78 = SMCDataType("sp78")
    /// Unsigned fixed point, 8 integer bits and 8 fraction bits, big-endian.
    public static let fp88 = SMCDataType("fp88")
    public static let ui8 = SMCDataType("ui8 ")
    public static let ui16 = SMCDataType("ui16")
    public static let ui32 = SMCDataType("ui32")
    public static let si8 = SMCDataType("si8 ")
    public static let si16 = SMCDataType("si16")
    public static let flag = SMCDataType("flag")
}

/// A key's raw bytes together with its declared type.
public struct SMCValue: Sendable, Equatable {
    public let key: SMCKey
    public let dataType: SMCDataType
    public let bytes: [UInt8]

    public init(key: SMCKey, dataType: SMCDataType, bytes: [UInt8]) {
        self.key = key
        self.dataType = dataType
        self.bytes = bytes
    }

    /// The value decoded as a number, or `nil` if the type is not numeric or the size is unexpected.
    public var doubleValue: Double? {
        switch (dataType, bytes.count) {
        case (.flt, 4):
            return Double(Float(bitPattern: littleEndian32))
        case (.fpe2, 2):
            return Double(bigEndian16) / 4
        case (.sp78, 2):
            return Double(Int16(bitPattern: bigEndian16)) / 256
        case (.fp88, 2):
            return Double(bigEndian16) / 256
        case (.ui8, 1), (.flag, 1):
            return Double(bytes[0])
        case (.si8, 1):
            return Double(Int8(bitPattern: bytes[0]))
        case (.ui16, 2):
            return Double(bigEndian16)
        case (.si16, 2):
            return Double(Int16(bitPattern: bigEndian16))
        case (.ui32, 4):
            return Double(bigEndian32)
        default:
            return nil
        }
    }

    private var bigEndian16: UInt16 { UInt16(bytes[0]) << 8 | UInt16(bytes[1]) }

    private var bigEndian32: UInt32 { bytes.reduce(0) { $0 << 8 | UInt32($1) } }

    private var littleEndian32: UInt32 { bytes.reversed().reduce(0) { $0 << 8 | UInt32($1) } }
}

public extension SMCDataType {
    /// Encodes `value` in this type's byte layout, or returns `nil` for types that cannot be written
    /// and for values that aren't finite in the type (NaN or infinity would trap or reach the SMC).
    func encode(_ value: Double) -> [UInt8]? {
        guard value.isFinite else { return nil }
        switch self {
        case .flt:
            let float = Float(value)
            guard float.isFinite else { return nil }
            let bits = float.bitPattern
            return [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: bits >> $0) }
        case .fpe2:
            // Clamped as a Double: converting a huge value to Int first would trap.
            let raw = UInt16(min(max((value * 4).rounded(), 0), Double(UInt16.max)))
            return [UInt8(raw >> 8), UInt8(truncatingIfNeeded: raw)]
        case .ui8, .flag:
            return [UInt8(min(max(value.rounded(), 0), Double(UInt8.max)))]
        default:
            return nil
        }
    }
}
