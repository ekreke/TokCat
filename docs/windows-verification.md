# 在 macOS 上验证 Windows 版（UTM · Windows 11 ARM）

TokCat 的 Windows 版是一个单文件 `TokCat.exe`（内嵌 .NET 自包含运行时 + Swift 引擎 + Swift 运行时 DLL）。
本机是 Apple Silicon，无法直接运行 Windows PE，因此用 **UTM（免费）** 装一个 **Windows 11 ARM** 虚拟机来验证。

> 产物是 `win-x64`，在 Windows 11 ARM 上由系统 x64 模拟执行（可用，略慢）。
> 逻辑/打包/CLI 运行时已由 CI 自动覆盖；本文档用于人工确认**托盘 UI**与**缺 DLL 问题已修复**。

## 1. 安装 UTM

```bash
brew install --cask utm
```

或用 https://mac.getutm.app 的非沙盒版；Mac App Store 版也可。要求 macOS 12+。

## 2. 获取 Windows 11 ARM64 ISO

- 用 **CrystalFetch**（Mac App Store 免费）从微软拉取官方 Windows 11 ARM64 ISO。
- 体积约 5GB；宿主机预留 ≥ 64GB 磁盘。

## 3. 建虚拟机（UTM）

1. **File → New → Virtualize → Windows**。
2. 选择刚下好的 ARM64 ISO（UTM 会识别 Win11 模板）。
3. 规格：**CPU 4–6 核 / 内存 8GB / 磁盘 64GB**。
4. 保持 **Secure Boot + TPM** 开启。
5. 启动并按向导安装；可「我没有产品密钥」；若卡在联网/账号，`Shift+F10` 打开命令行，输入 `oobe\bypassnro` 建本地账号。
6. （可选）安装 UTM 的 **SPICE 客户机工具**，改善显示与拖放。

## 4. 安装前置依赖

VM 内安装 **VC++ 2015–2022 Redistributable (x64)**：

```powershell
winget install --id Microsoft.VCRedist.2015+.x64
```

> 我们已内嵌 Swift 运行时 DLL；但 Swift 运行时本身可能依赖 `vcruntime140.dll` / `msvcp140.dll`（Windows 通常自带）。
> **若启动时报缺这两个 DLL，就是没装该 redist。**

## 5. 把 `TokCat.exe` 放进 VM

在 VM 的浏览器里直接打开：

```
https://github.com/ekreke/TokCat/releases/latest/download/TokCat.exe
```

（或用 UTM 共享目录 / 拖放。）

## 6. 验证清单

1. **双击 `TokCat.exe`** → 如遇 SmartScreen，点「更多信息 → 仍要运行」。首次运行会自解压到 `%LOCALAPPDATA%\TokCat\`。
2. **直接验证 CLI 自包含（最关键的一步，复现此前报错点）** —— VM 里开 PowerShell：
   ```powershell
   & "$env:LOCALAPPDATA\TokCat\TokCatCli.exe" version
   ```
   → 应打印 `TokCatCli 0.1.6`，**不再弹出 `swiftCore.dll / swift_Concurrency.dll / swiftWinSDK.dll` 缺失错误**。
   进一步：`& "$env:LOCALAPPDATA\TokCat\TokCatCli.exe" dump` 打印各采集源统计。
3. 确认 `%LOCALAPPDATA%\TokCat\` 中除 `TokCatCli.exe` 外，还有一批 `swift*.dll` / `Foundation*.dll` 等运行时。
4. **托盘**：出现猫图标；空闲慢走（约 2fps）。
5. **左键**：弹出状态窗（当前速率 / 合计 / 来源列表）。
6. **右键菜单**逐项点：速率口径 / 尺寸 / 最大帧率 / 灵敏度 / 数据源 / 重载模型定价 / 重置统计 / 开机自启 / 退出。
7. （可选）勾选「开机自启」后重启 VM，确认自动出现托盘图标。

## 7. （可选）让猫动起来

全新 VM 没有 agent 数据，速率会保持 0（猫慢走）。想看变速，可造一份 Claude 日志：

在 VM 中新建 `%USERPROFILE%\.claude\projects\demo\demo.jsonl`，写入若干行（`id` 各不相同）：

```json
{"timestamp":"2026-09-15T10:00:00.000Z","message":{"id":"m1","model":"gpt-4o","usage":{"input_tokens":50000,"output_tokens":2000}}}
{"timestamp":"2026-09-15T10:00:01.000Z","message":{"id":"m2","model":"gpt-4o","usage":{"input_tokens":40000,"output_tokens":1500}}}
```

然后**重启 TokCat**（JSONL 采集源首次从 0 偏移读取）→ 启动瞬间产生消耗，猫会加速再回落。仅验托盘/菜单可跳过。

## 8. 常见问题

| 现象 | 处理 |
|---|---|
| 报 `vcruntime140.dll` / `msvcp140.dll` 缺失 | 执行第 4 步安装 VC++ Redistributable |
| 首次启动稍慢 | 正常（自解压运行时 + 单文件原生库解压） |
| SmartScreen 拦截 | 未签名，属预期；「更多信息 → 仍要运行」 |
| x64 模拟略慢 | 预期（win-x64 在 Win11 ARM 上模拟执行） |

## 9. 无需 Windows 也能验证的部分

- **CI（GitHub Actions `windows-latest`）** 已自动覆盖：Swift 编译与单测、C# 编译、单文件打包，以及**清空 PATH 后运行 `TokCatCli.exe` 的自包含冒烟**。
- 因此本 VM 只需确认**托盘 UI**与**上面的第 6 步**即可。
