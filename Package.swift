// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PetNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "PetNative",
            targets: ["PetNative"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PetNative",
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
                    "-Xlinker", "Sources/PetNative/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "PetNativeTests",
            dependencies: ["PetNative"]
        ),
    ]
)
