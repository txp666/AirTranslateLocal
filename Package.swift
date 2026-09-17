// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AirTranslate",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "AirTranslate", targets: ["AirTranslate"])
    ],
    targets: [
        .target(name: "AirTranslateCore"),
        .executableTarget(
            name: "AirTranslate",
            dependencies: ["AirTranslateCore"],
            linkerSettings: [
                .linkedFramework("AVFAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech")
            ]
        ),
        .testTarget(
            name: "AirTranslateCoreTests",
            dependencies: [
                "AirTranslateCore",
                "AirTranslate"
            ]
        )
    ]
)
