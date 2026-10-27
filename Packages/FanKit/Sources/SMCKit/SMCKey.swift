/// A four-character SMC key such as `F0Ac` or `Tp01`, stored as a big-endian `UInt32`.
public struct SMCKey: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let code: UInt32

    public init(code: UInt32) {
        self.code = code
    }

    /// Creates a key from a four-character ASCII string.
    public init(_ name: String) {
        precondition(name.utf8.count == 4, "SMC keys are exactly four ASCII characters: \(name)")
        code = FourCC.code(string: name)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var name: String { FourCC.string(from: code) }

    public var description: String { name }
}

// MARK: - Well-known keys

public extension SMCKey {
    /// Total number of keys exposed by the SMC (`ui32`).
    static let keyCount: SMCKey = "#KEY"

    /// Number of fans (`ui8`).
    static let fanCount: SMCKey = "FNum"

    /// Whether `fan` fits the four-character fan keys below (`F0Ac` … `F9Ac`). Check before building a key
    /// from an untrusted index; an invalid one traps.
    static func isValidFanIndex(_ fan: Int) -> Bool {
        FanLimits.addressable.contains(fan)
    }

    /// Current fan speed in RPM.
    static func fanActual(_ fan: Int) -> SMCKey { SMCKey("F\(fan)Ac") }

    /// Lowest speed the fan is allowed to run at, in RPM.
    static func fanMinimum(_ fan: Int) -> SMCKey { SMCKey("F\(fan)Mn") }

    /// Highest speed the fan can run at, in RPM.
    static func fanMaximum(_ fan: Int) -> SMCKey { SMCKey("F\(fan)Mx") }

    /// Target speed in RPM. Only honoured while the fan is in manual mode.
    static func fanTarget(_ fan: Int) -> SMCKey { SMCKey("F\(fan)Tg") }

    /// Fan mode: `0` automatic (SMC controlled), `1` manual (`ui8`).
    static func fanMode(_ fan: Int) -> SMCKey { SMCKey("F\(fan)Md") }
}

// MARK: - FourCC helpers

enum FourCC {
    static func string(from code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func code(string: String) -> UInt32 {
        string.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
}
