import IOKit

public enum SMCError: Error, Equatable, CustomStringConvertible {
    case serviceNotFound
    case keyNotFound(SMCKey)
    case sizeMismatch(SMCKey, expected: Int, actual: Int)
    /// Writing to the SMC requires root. The app delegates writes to the privileged helper.
    case notPrivileged
    case unsupportedType(SMCKey, SMCDataType)
    case smc(code: UInt8)
    case ioKit(kern_return_t)

    public var description: String {
        switch self {
        case .serviceNotFound:
            return "AppleSMC service not found"
        case .keyNotFound(let key):
            return "SMC key \(key) not found"
        case .sizeMismatch(let key, let expected, let actual):
            return "SMC key \(key) expects \(expected) bytes, got \(actual)"
        case .notPrivileged:
            return "Writing to the SMC requires root privileges"
        case .unsupportedType(let key, let type):
            return "Cannot encode a value for SMC key \(key) of type \(type)"
        case .smc(let code):
            return "SMC returned error 0x\(String(code, radix: 16))"
        case .ioKit(let code):
            return "IOKit error 0x\(String(UInt32(bitPattern: code), radix: 16))"
        }
    }
}

/// A connection to the System Management Controller.
///
/// Not thread-safe: own it from a single actor or thread.
public final class SMC {
    private var connection: io_connect_t = 0
    private var keyInfoCache: [SMCKey: SMCParamStruct.KeyInfo] = [:]

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.ioKit(result) }
    }

    deinit {
        IOServiceClose(connection)
    }

    // MARK: Reading

    public func read(_ key: SMCKey) throws -> SMCValue {
        let info = try keyInfo(for: key)

        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = SMCCommand.readKey

        let output = try call(input, key: key)
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return SMCValue(key: key, dataType: SMCDataType(code: info.dataType), bytes: bytes)
    }

    /// Reads `key` and decodes it as a number. Returns `nil` if the key is missing or not numeric.
    public func readDouble(_ key: SMCKey) -> Double? {
        try? read(key).doubleValue
    }

    // MARK: Writing

    /// Writes raw bytes to `key`. Requires root.
    public func write(_ key: SMCKey, bytes: [UInt8]) throws {
        let info = try keyInfo(for: key)
        guard bytes.count == Int(info.dataSize) else {
            throw SMCError.sizeMismatch(key, expected: Int(info.dataSize), actual: bytes.count)
        }

        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = SMCCommand.writeKey
        withUnsafeMutableBytes(of: &input.bytes) { $0.copyBytes(from: bytes) }

        _ = try call(input, key: key)
    }

    /// Encodes `value` using the key's own data type and writes it. Requires root.
    public func write(_ key: SMCKey, value: Double) throws {
        let type = SMCDataType(code: try keyInfo(for: key).dataType)
        guard let bytes = type.encode(value) else {
            throw SMCError.unsupportedType(key, type)
        }
        try write(key, bytes: bytes)
    }

    // MARK: Enumeration

    /// Every key the SMC exposes. Slow (one call per key); intended for diagnostics.
    public func allKeys() throws -> [SMCKey] {
        let count = Int(try read(.keyCount).doubleValue ?? 0)
        return try (0..<count).map { index in
            var input = SMCParamStruct()
            input.data8 = SMCCommand.keyFromIndex
            input.data32 = UInt32(index)
            return SMCKey(code: try call(input, key: nil).key)
        }
    }

    public func dataType(of key: SMCKey) throws -> SMCDataType {
        SMCDataType(code: try keyInfo(for: key).dataType)
    }

    // MARK: Private

    private func keyInfo(for key: SMCKey) throws -> SMCParamStruct.KeyInfo {
        if let cached = keyInfoCache[key] { return cached }

        var input = SMCParamStruct()
        input.key = key.code
        input.data8 = SMCCommand.keyInfo

        let info = try call(input, key: key).keyInfo
        keyInfoCache[key] = info
        return info
    }

    private func call(_ input: SMCParamStruct, key: SMCKey?) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection,
            kSMCHandleYPCEvent,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )

        switch result {
        case kIOReturnSuccess:
            break
        case kIOReturnNotPrivileged:
            throw SMCError.notPrivileged
        default:
            throw SMCError.ioKit(result)
        }

        switch output.result {
        case SMCResult.success:
            return output
        case SMCResult.keyNotFound:
            throw SMCError.keyNotFound(key ?? SMCKey(code: input.key))
        default:
            throw SMCError.smc(code: output.result)
        }
    }
}

/// `iokit_common_err(0x2c1)`; the C macro is not imported into Swift.
private let kIOReturnNotPrivileged = kern_return_t(bitPattern: 0xE000_02C1)
