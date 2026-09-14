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
        .library(name: "TokCatAgent", targets: ["TokCatAgent"]),
    ],
    targets: [
        .target(
            name: "TokCatCore"
        ),
        .target(
            name: "TokCatSources",
            dependencies: ["TokCatCore"]
        ),
        .target(
            name: "TokCatAgent",
            dependencies: ["TokCatCore"]
        ),
        .executableTarget(
            name: "TokCatApp",
            dependencies: ["TokCatCore", "TokCatSources", "TokCatAgent"],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "TokCatCoreTests",
            dependencies: ["TokCatCore"]
        ),
        .testTarget(
            name: "TokCatSourcesTests",
            dependencies: ["TokCatSources", "TokCatCore"]
        ),
        .testTarget(
            name: "TokCatAgentTests",
            dependencies: ["TokCatAgent", "TokCatCore"],
            exclude: ["Fixtures"]
        ),
    ]
)
