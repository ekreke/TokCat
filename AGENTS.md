# AGENTS.md

TokCat：菜单栏应用，跟随本机 AI agent 的 token 消耗速率播放奔跑动画。Swift + SwiftPM，双平台（macOS 13+ / Windows）。文档与代码注释一律用中文。

## 常用命令

```bash
make build            # swift build（同时就是类型检查；本仓库无 lint/formatter 工具）
make test             # swift test
swift test --filter TokCatCoreTests   # 跑单个测试 target
make run              # swift run TokCat（macOS 菜单栏应用）
make app              # ./Scripts/make-app.sh release，组装 build/TokCat.app
make dmg              # ./Scripts/make-dmg.sh
make dump             # swift run TokCat dump，打印各采集源统计（诊断）
swift build --product TokCatCli       # 验证 Windows 共享层是否仍可独立编译
dotnet build windows/TokCat.Windows/TokCat.Windows.csproj -c Release   # Windows UI（需 .NET 8）
```

发布不打 `make`：打 `v*` tag 触发 `.github/workflows/release.yml`（DMG + 更新 Cask）和 `release-windows.yml`（单文件 TokCat.exe）。CI 只在 `main` / `feat/**` / `spike/**` / `fix/**` 分支和 PR 上跑。

## 架构：一个包，两种平台

`Package.swift` 顶层用 `#if os(...)` 分割 target，这是本仓库最重要的约束：

- **共享层**（macOS + Windows 都编译，零第三方依赖）：`TokCatCore`（模型/速率/动画）→ `TokCatSources`（各 agent 日志/DB 采集，依赖 SQLite）→ `TokCatAgent`（ACP JSON-RPC 客户端，含 SSH 远程）→ `TokCatEngine`（聚合）→ `TokCatCli`（常驻 CLI，子命令 `serve` 默认 / `dump` / `version`）。
- **仅 macOS**：`TokCatApp`（AppKit/SwiftUI 外壳），依赖 MarkdownUI + HighlighterSwift。
- **仅 Windows**：`Sources/SQLite3`（systemLibrary）+ `windows/TokCat.Windows/` 是 **C#/.NET 8** 托盘应用，不是 Swift；它内嵌 `TokCatCli.exe` 作为引擎（打包进 `Payload/`，运行时自解压到 `%LOCALAPPDATA%\TokCat\`）。

**规则**：共享层源码禁止 import AppKit/SwiftUI/Maps 等 Apple-only 框架，否则 Windows CI（`swift build --product TokCatCli` + `swift test`）必挂。改共享层后至少本地跑一次该命令。

**SQLite**：不 vendor。Apple 用 SDK 内置 `SQLite3` 模块，Windows 用 winsqlite3（`Sources/SQLite3/` 仅在 Windows 声明同名模块）。源码两端统一写 `import SQLite3`，依赖数组用 Package.swift 顶部的 `sqliteDependency` 变量。

## 构建陷阱

- `Sources/TokCatCli/BuildVersion.swift` 是 **CI 生成文件**（release 流程直接覆写注入版本号）。不要手改它发版，改了也会被覆盖；本地保留默认值即可。
- `make app` 会把 SPM 资源 bundle（`*.bundle`，内置动画素材）拷进 `Contents/Resources/`——缺了它 `Bundle.module` 运行时崩。自建 Info.plist 由脚本生成，`LSUIElement` 签名后由 main.swift 设为 accessory（无 Dock 图标）。
- 签名：脚本优先找 Developer ID（`CODESIGN_IDENTITY` 可覆盖），找不到退回 ad-hoc；开机自启（SMAppService）要求已签名。
- 版本号优先级：`VERSION` 环境变量 > 最近 git tag（去 `v` 前缀）> `0.1.0`。

## 测试

- 三个 target：`TokCatCoreTests` / `TokCatSourcesTests` / `TokCatAgentTests`，macOS 和 Windows CI 都会跑，所以测试代码本身也要跨平台。
- `Tests/TokCatAgentTests/Fixtures/` 已在 Package.swift 中 `exclude`，放 ACP 消息样例 JSON，不是测试源码。
- 采集器对日志格式变化采取「无法识别则跳过」的容错策略（见 README「已知边界」），改动解析逻辑时注意这一定位。

## 约定

- 注释、commit、文档全部中文；代码注释解释「为什么」而非「是什么」。
- Homebrew cask 在 `Casks/tokcat.rb`，release workflow 在发版时自动更新版本与 sha256，不要手改。
- Windows 人工验证流程（UTM 虚拟机）见 `docs/windows-verification.md`。
