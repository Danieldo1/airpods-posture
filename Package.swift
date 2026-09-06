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
    dependencies: [.package(path: "Vendor/ColorSelector")],
    targets: [
        .target(
            name: "AirPostureCore",
            path: "Sources/AirPostureCore"
        ),
        .executableTarget(
            name: "AirPosture",
            dependencies: ["AirPostureCore", .product(name: "ColorSelector", package: "ColorSelector")],
            path: "Sources/AirPostureMac",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "AirPostureMappingCheck",
            dependencies: ["AirPostureCore"],
            path: "Tests/AirPostureMappingCheck"
        ),
        .executableTarget(
            name: "AirPostureBustCheck",
            dependencies: ["AirPostureCore"],
            path: "Tests/AirPostureBustCheck"
        ),
        .executableTarget(
            name: "AirPostureFeatureCheck",
            dependencies: ["AirPostureCore"],
            path: "Tests/AirPostureFeatureCheck"
        )
    ]
)
