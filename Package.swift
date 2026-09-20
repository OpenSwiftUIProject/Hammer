// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "Hammer",
    platforms: [
        .iOS(.v15),
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
        // Use the Xcode project to run tests in TestHost on both platforms.
        .testTarget(
            name: "HammerTests",
            dependencies: ["Hammer"],
            exclude: ["Info.plist"]
        ),
    ]
)
