// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MaskMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MaskMac", targets: ["MaskMac"])
    ],
    targets: [
        .executableTarget(name: "MaskMac")
    ]
)
