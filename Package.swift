// swift-tools-version:5.9
import PackageDescription

// Package nay CHI de kiem tra tang LOGIC (Foundation-only) - khong chua SwiftUI/UIKit.
//   macOS : swift build && swift run BolaSelfTest
//   Linux : (swift 5.9+) swift run BolaSelfTest
// App iOS that build bang Xcode / XcodeGen (xem project.yml).
let package = Package(
    name: "BolaCore",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "BolaCore",
            path: "Sources",
            sources: [
                "Core/Crypto.swift",
                "Core/BolaConfig.swift",
                "Core/PatchTrailer.swift",
                "Core/Models.swift",
                "Core/Lease.swift",
                "Core/LicenseClient.swift",
                "Core/ContainerAccess.swift",
                "Core/KernelPrimitive.swift",
                "Core/ExploitCoordinator.swift",
                "Core/PatchDeployer.swift",
                "Core/PatchGuard.swift",
                "Core/PatchLibrary.swift",
                "Support/Logger.swift",
            ]
        ),
        .executableTarget(
            name: "BolaSelfTest",
            dependencies: ["BolaCore"],
            path: "verify",
            sources: ["main.swift"]
        ),
    ]
)
