// swift-tools-version: 5.10
import PackageDescription

// 共享层（跨平台）：Core / Sources / Agent 以及常驻 CLI。
// macOS 专属（AppKit / SwiftUI / Apple-only 依赖）仅在 macOS 上声明，
// 保证 Windows 构建共享层时不会解析、编译 Apple-only 包。

var products: [Product] = [
    .library(name: "TokCatCore", targets: ["TokCatCore"]),
    .library(name: "TokCatSources", targets: ["TokCatSources"]),
    .library(name: "TokCatAgent", targets: ["TokCatAgent"]),
    .executable(name: "TokCatCli", targets: ["TokCatCli"]),
]

var dependencies: [Package.Dependency] = []

var targets: [Target] = [
    // 自带 SQLite amalgamation，避免依赖各平台系统 libsqlite3。
    .target(name: "CSQLite", path: "Sources/CSQLite", publicHeadersPath: "include"),
    .target(name: "TokCatCore"),
    .target(name: "TokCatSources", dependencies: ["TokCatCore", "CSQLite"]),
    .target(name: "TokCatAgent", dependencies: ["TokCatCore"]),
    .executableTarget(
        name: "TokCatCli",
        dependencies: ["TokCatCore", "TokCatSources", "TokCatAgent"]
    ),
    .testTarget(name: "TokCatCoreTests", dependencies: ["TokCatCore"]),
    .testTarget(name: "TokCatSourcesTests", dependencies: ["TokCatSources", "TokCatCore", "CSQLite"]),
    .testTarget(name: "TokCatAgentTests", dependencies: ["TokCatAgent", "TokCatCore"], exclude: ["Fixtures"]),
]

#if os(macOS)
dependencies.append(.package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"))
dependencies.append(.package(url: "https://github.com/smittytone/HighlighterSwift", from: "3.1.0"))
products.append(.executable(name: "TokCat", targets: ["TokCatApp"]))
targets.append(
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
    )
)
#endif

let package = Package(
    name: "TokCat",
    platforms: [
        .macOS(.v13)
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
