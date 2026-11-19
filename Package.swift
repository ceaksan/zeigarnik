// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Zeigarnik",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZeigarnikCore", targets: ["ZeigarnikCore"]),
        .library(name: "ZeigarnikKit", targets: ["ZeigarnikKit"]),
        .library(name: "ZeigarnikUI", targets: ["ZeigarnikUI"]),
        .executable(name: "zeigarnik-scan", targets: ["ZeigarnikScan"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.12.0"),
    ],
    targets: [
        .target(
            name: "ZeigarnikCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "ZeigarnikKit",
            dependencies: ["ZeigarnikCore"]
        ),
        .target(
            name: "ZeigarnikUI",
            dependencies: ["ZeigarnikKit"]
        ),
        .executableTarget(
            name: "ZeigarnikScan",
            dependencies: ["ZeigarnikCore"]
        ),
        .testTarget(
            name: "ZeigarnikCoreTests",
            dependencies: ["ZeigarnikCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "ZeigarnikKitTests",
            dependencies: ["ZeigarnikKit"]
        ),
    ]
)
