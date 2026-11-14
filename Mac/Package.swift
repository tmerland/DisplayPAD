// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DisplayPADMac",
    platforms: [.macOS(.v14)],
    targets: [
        // Déclarations Objective-C des classes privées CGVirtualDisplay*
        .target(name: "CGVirtualDisplayBridge", path: "CGVirtualDisplayBridge"),
        .executableTarget(
            name: "DisplayPADMac",
            dependencies: ["CGVirtualDisplayBridge"],
            path: "DisplayPADMac/Sources"
        ),
    ]
)
