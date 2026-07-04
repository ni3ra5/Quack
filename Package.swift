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
    dependencies: [
        // Local sub-package for the vendored MediaRemoteAdapter dylib. Kept as
        // a separate package (not same-package targets) so Quack consumes it
        // as a genuine product dependency and SwiftPM links it dynamically
        // via @rpath instead of statically embedding it — see the comment atop
        // Sources/MediaRemoteAdapterPkg/Package.swift for why that split is
        // required.
        .package(path: "Sources/MediaRemoteAdapterPkg"),
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
        // The app target: SwiftUI + AppKit + system frameworks. Wires QuackKit
        // logic to live services (EventKit, UserNotifications, IOKit DDC, AX).
        .executableTarget(
            name: "Quack",
            dependencies: [
                "QuackKit", "CDDC", "CMultitouch", "CSMC",
                // Dynamic-library product from the local sub-package (see
                // dependencies: above) — resolves to libMediaRemoteAdapter.dylib
                // linked via @rpath, not statically embedded.
                .product(name: "MediaRemoteAdapter", package: "MediaRemoteAdapterPkg"),
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "QuackKitTests",
            dependencies: ["QuackKit"]
        ),
    ]
)
