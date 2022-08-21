// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CachingPlayerItem",
    defaultLocalization: "en",
    platforms: [.iOS(.v10)],
    products: [
        .library(
            name: "CachingPlayerItem",
            targets: ["CachingPlayerItem"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CachingPlayerItem",
            dependencies: [],
            path: "Source"
        )
    ]
)
