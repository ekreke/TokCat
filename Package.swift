// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TokCat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TokCat", targets: ["TokCatApp"]),
        .library(name: "TokCatCore", targets: ["TokCatCore"]),
        .library(name: "TokCatSources", targets: ["TokCatSources"]),
    ],
    targets: [
        .target(
            name: "TokCatCore"
        ),
        .target(
            name: "TokCatSources",
            dependencies: ["TokCatCore"]
        ),
        .executableTarget(
            name: "TokCatApp",
            dependencies: ["TokCatCore", "TokCatSources"]
        ),
        .testTarget(
            name: "TokCatCoreTests",
            dependencies: ["TokCatCore"]
        ),
        .testTarget(
            name: "TokCatSourcesTests",
            dependencies: ["TokCatSources", "TokCatCore"]
        ),
    ]
)
