// swift-tools-version: 5.10
import PackageDescription

// 共享层（跨平台）：Core / Sources / Agent 以及常驻 CLI。
// macOS 专属（AppKit / SwiftUI / Apple-only 依赖）仅在 macOS 上声明，
// 保证 Windows 构建共享层时不会解析、编译 Apple-only 包。
//
// SQLite：不 vendor，直接用各平台系统实现。
// - macOS/Apple：SDK 内置的 `SQLite3` 模块。
// - Windows：Windows SDK 自带的 `winsqlite3`（运行时 winsqlite3.dll 随系统）。
//   Windows 上声明一个名为 `SQLite3` 的 systemLibrary，使源码两端都能 `import SQLite3`。

/// Windows 才需要显式声明 SQLite 依赖；Apple 平台由 SDK 提供。
#if os(Windows)
let sqliteDependency: [Target.Dependency] = ["SQLite3"]
#else
let sqliteDependency: [Target.Dependency] = []
#endif

var products: [Product] = [
    .library(name: "TokCatCore", targets: ["TokCatCore"]),
    .library(name: "TokCatSources", targets: ["TokCatSources"]),
    .library(name: "TokCatAgent", targets: ["TokCatAgent"]),
    .executable(name: "TokCatCli", targets: ["TokCatCli"]),
]

var dependencies: [Package.Dependency] = []

var targets: [Target] = [
    .target(name: "TokCatCore"),
    .target(name: "TokCatSources", dependencies: ["TokCatCore"] + sqliteDependency),
    .target(name: "TokCatAgent", dependencies: ["TokCatCore"]),
    .executableTarget(
        name: "TokCatCli",
        dependencies: ["TokCatCore", "TokCatSources", "TokCatAgent"]
    ),
    .testTarget(name: "TokCatCoreTests", dependencies: ["TokCatCore"]),
    .testTarget(name: "TokCatSourcesTests", dependencies: ["TokCatSources", "TokCatCore"] + sqliteDependency),
    .testTarget(name: "TokCatAgentTests", dependencies: ["TokCatAgent", "TokCatCore"], exclude: ["Fixtures"]),
]

#if os(Windows)
// 把 Windows SDK 的 winsqlite3 暴露成 `SQLite3` 模块。
targets.append(.systemLibrary(name: "SQLite3", path: "Sources/SQLite3"))
#endif

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
