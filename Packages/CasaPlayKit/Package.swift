// swift-tools-version: 5.9
// CasaPlayKit: the platform-independent core of CasaPlay.
// Designed by 𝐂𝓪sΔηⓞשα.

import PackageDescription

let package = Package(
    name: "CasaPlayKit",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CasaPlayKit", targets: ["CasaPlayKit"])
    ],
    targets: [
        .target(name: "CasaPlayKit"),
        .testTarget(name: "CasaPlayKitTests", dependencies: ["CasaPlayKit"])
    ]
)
