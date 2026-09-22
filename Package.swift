// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ntfs-manager",
    defaultLocalization: "ko",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NTFSKit", targets: ["NTFSKit"]),
        .executable(name: "ntfs-manager", targets: ["NTFSManager"]),
    ],
    targets: [
        .target(
            name: "NTFSKit",
            path: "Sources/NTFSKit"
        ),
        .executableTarget(
            name: "NTFSManager",
            dependencies: ["NTFSKit"],
            path: "Sources/NTFSManager"
        ),
        .executableTarget(
            name: "ntfs-cli",
            dependencies: ["NTFSKit"],
            path: "Sources/ntfs-cli",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ntfs-helper",
            path: "Sources/ntfs-helper"
        ),
    ]
)
