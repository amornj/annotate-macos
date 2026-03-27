// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AnnotateMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AnnotateMac", targets: ["AnnotateMac"])
    ],
    targets: [
        .executableTarget(
            name: "AnnotateMac",
            path: "macos/Sources"
        )
    ]
)
