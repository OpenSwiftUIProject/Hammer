// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "Hammer",
    platforms: [
        .iOS(.v12),
        .macOS(.v12),
    ],
    products: [
        .library(name: "Hammer", targets: ["Hammer"]),
    ],
    targets: [
        .target(
          name: "Hammer",
          exclude: ["Info.plist"]
        ),
        .testTarget(name: "HammerAppKitTests", dependencies: ["Hammer"]),
        // Disabled because SPM does not support running on TestHost yet
        // .testTarget(name: "HammerTests", dependencies: ["Hammer"]),
    ]
)
