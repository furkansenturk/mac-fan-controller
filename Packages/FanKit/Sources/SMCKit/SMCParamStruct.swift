import IOKit

/// Swift mirror of the kernel's `SMCParamStruct` (80 bytes).
///
/// Swift places each stored property at the next suitably aligned offset after the previous
/// property's *size*, not its stride, so `padding` is needed to reproduce the C layout after
/// `keyInfo` (9 bytes in Swift, 12 in C). `SMCParamStructTests` pins every offset.
struct SMCParamStruct {
    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    var key: UInt32 = 0
    var version = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

/// Commands placed in `SMCParamStruct.data8`.
enum SMCCommand {
    static let readKey: UInt8 = 5
    static let writeKey: UInt8 = 6
    static let keyFromIndex: UInt8 = 8
    static let keyInfo: UInt8 = 9
}

/// Values the SMC returns in `SMCParamStruct.result`.
enum SMCResult {
    static let success: UInt8 = 0
    static let keyNotFound: UInt8 = 0x84
}

/// `AppleSMC` user client method that accepts an `SMCParamStruct`.
let kSMCHandleYPCEvent: UInt32 = 2
