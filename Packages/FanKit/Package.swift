// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FanKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SMCKit", targets: ["SMCKit"]),
        .library(name: "FanKit", targets: ["FanKit"]),
        .library(name: "FanXPC", targets: ["FanXPC"]),
        .executable(name: "smc-dump", targets: ["smc-dump"]),
    ],
    targets: [
        // Raw access to the System Management Controller. The only module that talks to IOKit.
        .target(
            name: "SMCKit",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // C declarations for the IOHID temperature sensors Apple Silicon exposes outside the SMC.
        .target(
            name: "CIOHID",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Domain layer: fans, temperature sensors and the key → name catalog.
        .target(
            name: "FanKit",
            dependencies: ["SMCKit", "CIOHID"]
        ),
        // The XPC contract shared by the app and the privileged helper.
        .target(name: "FanXPC"),
        // Diagnostic tool used for model support reports.
        .executableTarget(
            name: "smc-dump",
            dependencies: ["SMCKit", "FanKit"]
        ),
        .testTarget(name: "SMCKitTests", dependencies: ["SMCKit"]),
        .testTarget(name: "FanKitTests", dependencies: ["FanKit"]),
    ]
)
