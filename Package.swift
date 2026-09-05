// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AirPostureMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AirPosture", targets: ["AirPosture"]),
        .library(name: "AirPostureCore", targets: ["AirPostureCore"])
    ],
    targets: [
        .target(
            name: "AirPostureCore",
            path: "Sources/AirPostureCore"
        ),
        .executableTarget(
            name: "AirPosture",
            dependencies: ["AirPostureCore"],
            path: "Sources/AirPostureMac"
        ),
        .executableTarget(
            name: "AirPostureMappingCheck",
            dependencies: ["AirPostureCore"],
            path: "Tests/AirPostureMappingCheck"
        )
    ]
)
