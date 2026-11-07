// swift-tools-version: 5.9
// iOS port (Chesly fork, 2026-11): gate G1. Runs ntgcalls beside the WebRTC build LiveKit's Swift
// SDK 2.19.0 pins, on the iPhone simulator. ntgcalls.xcframework is unpacked next to this file by
// the workflow.
import PackageDescription

let package = Package(
    name: "NtgcallsG1",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "G1Support", targets: ["G1Support"]),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/webrtc-xcframework.git", exact: "150.7871.04"),
    ],
    targets: [
        .binaryTarget(name: "ntgcalls", path: "ntgcalls.xcframework"),
        .target(name: "G1Support", dependencies: ["ntgcalls"]),
        .testTarget(
            name: "G1Tests",
            dependencies: [
                "G1Support",
                "ntgcalls",
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework"),
            ]
        ),
    ]
)
