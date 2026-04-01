// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mac_worker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "mac_worker", targets: ["mac_worker"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "mac_worker",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
