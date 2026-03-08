// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MicCheck",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "MicCheck", targets: ["MicCheck"]),
    ],
    targets: [
        .executableTarget(
            name: "MicCheck",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        ),
        .testTarget(
            name: "MicCheckTests",
            dependencies: ["MicCheck"]
        ),
    ]
)
