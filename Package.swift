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
        // iOS tests require TestHost through Xcode; SwiftPM runs the macOS tests.
        .testTarget(
            name: "HammerTests",
            dependencies: ["Hammer"],
            exclude: ["Info.plist"]
        ),
    ]
)
