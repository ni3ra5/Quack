// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Quack",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Quack", targets: ["Quack"]),
        .library(name: "QuackKit", targets: ["QuackKit"]),
    ],
    targets: [
        // Pure, side-effect-free logic. Fully unit-testable, no GUI/system deps.
        .target(
            name: "QuackKit"
        ),
        // C shim for DDC/CI brightness over the private IOAVService API.
        .target(
            name: "CDDC",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        // C shim for raw trackpad touches over the private MultitouchSupport API
        // (loaded at runtime via dlopen — see CMultitouch.c).
        .target(
            name: "CMultitouch",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
            ]
        ),
        // C shim for CPU temperature via the SMC over IOKit.
        .target(
            name: "CSMC",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        // Vendored (ejbills/mediaremote-adapter @ cf30c4f, BSD-3-Clause):
        // ObjC resolver for private MediaRemote symbols. Compiled without ARC.
        .target(
            name: "CIMediaRemote",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fno-objc-arc"])],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        // Vendored: Swift controller that spawns /usr/bin/perl + run.pl to load
        // the CIMediaRemote dylib and stream/command now-playing over pipes.
        .target(
            name: "MediaRemoteAdapter",
            dependencies: ["CIMediaRemote"],
            exclude: ["LICENSE", "VENDORED.md"],
            resources: [.copy("Resources/run.pl")]
        ),
        // The app target: SwiftUI + AppKit + system frameworks. Wires QuackKit
        // logic to live services (EventKit, UserNotifications, IOKit DDC, AX).
        .executableTarget(
            name: "Quack",
            dependencies: ["QuackKit", "CDDC", "CMultitouch", "CSMC", "MediaRemoteAdapter"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .testTarget(
            name: "QuackKitTests",
            dependencies: ["QuackKit"]
        ),
    ]
)
