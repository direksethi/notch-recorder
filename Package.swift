// swift-tools-version: 6.2
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "NotchRecorder",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "NotchRecorder", targets: ["NotchRecorder"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "Common", swiftSettings: swift5),
        .target(
            name: "LibraryKit",
            dependencies: ["Common", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: swift5),
        .target(name: "RecorderKit", dependencies: ["Common"], swiftSettings: swift5),
        .target(
            name: "TranscriptKit",
            dependencies: ["Common", .product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: swift5),
        .target(name: "BridgeKit", dependencies: ["Common", "LibraryKit"], swiftSettings: swift5),
        .target(name: "LiveUI", dependencies: ["Common"], swiftSettings: swift5),
        .executableTarget(
            name: "NotchRecorder",
            dependencies: ["Common", "LibraryKit", "RecorderKit", "TranscriptKit", "BridgeKit", "LiveUI"],
            swiftSettings: swift5),
        .executableTarget(name: "ASRCheck", dependencies: ["TranscriptKit"], swiftSettings: swift5),

        .testTarget(name: "LibraryKitTests", dependencies: ["LibraryKit"], swiftSettings: swift5),
        .testTarget(name: "RecorderKitTests", dependencies: ["RecorderKit"], swiftSettings: swift5),
        .testTarget(name: "TranscriptKitTests", dependencies: ["TranscriptKit"], swiftSettings: swift5),
        .testTarget(name: "BridgeKitTests", dependencies: ["BridgeKit"], resources: [.copy("Fixtures")], swiftSettings: swift5),
        .testTarget(name: "LiveUITests", dependencies: ["LiveUI"], swiftSettings: swift5),
        .testTarget(name: "NotchRecorderTests", dependencies: ["NotchRecorder"], swiftSettings: swift5),
    ]
)
