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
        // The app target: SwiftUI + AppKit + system frameworks. Wires QuackKit
        // logic to live services (EventKit, UserNotifications, IOKit DDC, AX).
        .executableTarget(
            name: "Quack",
            dependencies: ["QuackKit", "CDDC"],
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
