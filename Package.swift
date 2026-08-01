// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "CachingPlayerItem",
    defaultLocalization: "en",
    platforms: [
        .iOS("13.4"),
    ],
    products: [
        .library(name: "CachingPlayerItem", targets: ["CachingPlayerItem"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "CachingPlayerItem", dependencies: [], path: "Source"),
        .testTarget(name: "CachingPlayerItem_Tests",
                    dependencies: ["CachingPlayerItem"],
                    path: "Example/Tests"),
    ],
    swiftLanguageVersions: [
        .v5
    ]
)