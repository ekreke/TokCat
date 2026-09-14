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
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
        .package(url: "https://github.com/smittytone/HighlighterSwift", from: "3.1.0"),
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
            dependencies: [
                "TokCatCore",
                "TokCatSources",
                "TokCatAgent",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Highlighter", package: "HighlighterSwift"),
            ],
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
