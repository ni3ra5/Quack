// swift-tools-version: 5.9
import PackageDescription

// Local (path-based) sub-package, isolated from the root Quack package so that
// MediaRemoteAdapter can be a genuine *product* dependency of the Quack
// executable rather than a same-package target dependency.
//
// Why this split exists: SwiftPM always links a same-package target
// dependency by embedding its object code directly into the consumer's link
// job — a `type: .dynamic` library *product* wrapping that target has no
// effect on that, because products only govern how *other packages* consume
// a target, never how sibling targets within the same package link to it.
// Splitting MediaRemoteAdapter into its own local package makes Quack's
// dependency a cross-package product dependency, which SwiftPM resolves by
// linking against `libMediaRemoteAdapter.dylib` via `@rpath` instead of
// statically embedding it. Without this dylib, MediaController's runtime
// scheme (spawning /usr/bin/perl, which `dl_load_file`s
// `Bundle(for: MediaController.self).executablePath` and looks up exported C
// symbols) can't work — those symbols aren't exported from a static archive
// buried inside the Quack executable.
let package = Package(
    name: "MediaRemoteAdapterPkg",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MediaRemoteAdapter", type: .dynamic, targets: ["MediaRemoteAdapter"]),
    ],
    targets: [
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
    ]
)
