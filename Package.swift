// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MatrixCodeRainWallpaper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MatrixCodeRainWallpaper", targets: ["MatrixCodeRainWallpaper"])
    ],
    targets: [
        .executableTarget(
            name: "MatrixCodeRainWallpaper",
            path: "Sources/MatrixCodeRainWallpaper"
        )
    ]
)
