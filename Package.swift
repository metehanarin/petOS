// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "petOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "petOS",
            targets: ["petOS"]
        )
    ],
    targets: [
        .executableTarget(
            name: "petOS",
            exclude: [
                "Info.plist"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/petOS/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "petOSTests",
            dependencies: ["petOS"]
        ),
    ]
)
