// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PushPort",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "PushPort", targets: ["PushPort"]),
        .library(name: "PushPortNotificationService", targets: ["PushPortNotificationService"])
    ],
    targets: [
        .target(name: "PushPortCore"),
        .target(name: "PushPort", dependencies: ["PushPortCore"], resources: [.process("PrivacyInfo.xcprivacy")]),
        .target(name: "PushPortNotificationService", resources: [.process("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "PushPortCoreTests", dependencies: ["PushPortCore"]),
        .testTarget(name: "PushPortTests", dependencies: ["PushPort"])
    ]
)
