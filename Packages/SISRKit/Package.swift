// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SISRKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "SISRKit", targets: ["SISRKit"]),
    ],
    targets: [
        .target(
            name: "SISRKit",
            path: "Sources/SISRKit"
        ),
        .testTarget(
            name: "SISRKitTests",
            dependencies: ["SISRKit"],
            path: "Tests/SISRKitTests"
        ),
    ]
)
