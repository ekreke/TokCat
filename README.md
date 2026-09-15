# TokCat

<p align="center">
  <img src="docs/assets/cat_0.png" alt="TokCat" width="120" />
</p>

**你家菜单栏，该住一只跑得飞快的猫了。**

TokCat 跟着 AI 编码 agent 的 token 消耗速率跑动：烧得越猛，跑得越欢。灵感来自 [RunCat](https://github.com/runcat-dev/RunCat365)，但驱动的不是 CPU 占用，而是本机各个 agent 的 token 消耗速率。

支持 **macOS 13+（Apple Silicon）** 与 **Windows 10 19041+ / Windows 11（x64）**。

## 一只猫，干四件事

- 🏃 **速率动画** —— token/s 越高跑越快，空闲时以 2fps 慢走。内置 RunCat 精灵图，也支持自定义动画包。
- 💬 **左键 Chat** —— 常驻本地 agent 会话，流式回答、多轮追问，Markdown 渲染 + 代码高亮。
- 📊 **右键趋势** —— 菜单顶部内嵌最近 5 分钟折线，当前速率、合计、峰值一目了然。
- 🔌 **多源采集** —— opencode、Claude Code、Codex、pi、Hermes，以及可选的 cc-switch 聚合库。

## 它听得懂这些工具

从本地日志与数据库里算出你真实的 token 消耗速率，不上传任何数据。

`opencode` · `Claude Code` · `Codex` · `pi` · `Hermes` · `cc-switch`

## 安装

### 🍎 macOS

```bash
brew tap ekreke/tokcat https://github.com/ekreke/TokCat
brew trust --cask ekreke/tokcat/tokcat
brew install --cask tokcat
```

> Homebrew 7 起，非官方 tap 的 cask 需要先 `brew trust` 授权才能加载，且本 tap 使用自定义 remote，必须带 `--cask`。这是首次安装的一次性步骤。

升级 / 卸载：

```bash
brew upgrade --cask tokcat
brew uninstall --cask tokcat
```

TokCat 为 **ad-hoc 签名（未公证）**，仅支持 **Apple Silicon (arm64)**。Homebrew 安装一般不带 quarantine，可直接打开；若从 Releases 下载 DMG 后被拦截，右键 App →「打开」，或到「系统设置 → 隐私与安全性 → 仍要打开」（macOS 15+）。

### 🪟 Windows

1. 下载 [`TokCat.exe`](https://github.com/ekreke/TokCat/releases/latest/download/TokCat.exe)（单文件，免安装）
2. 双击运行；若 SmartScreen 提示，点「更多信息 → 仍要运行」
3. 托盘出现小猫，随 token 速率奔跑

更多下载见 [Releases](https://github.com/ekreke/TokCat/releases/latest)。

## 使用

### 左键：Chat（macOS）

- 通过 [ACP (Agent Client Protocol)](https://agentclientprotocol.com) 与本地 agent 通信，流式展示**正文 / 思考 / 工具 / 计划**。
- **常驻会话**：首次打开才连接（约 1–2s，之后秒开），关闭弹窗不结束会话，重开继续上次对话；空闲 1 小时才回收进程。
- 弹窗内可**多轮追问**，只显示最新回答；切换本地/远程、改目录或菜单「断开 Agent」会重连。
- 危险命令会弹出**授权条**（允许一次 / 允许会话 / 拒绝）。
- 回答以 **Markdown 渲染**：标题 / 列表 / 引用 / 表格 / 链接 / 代码块，代码块带**语法高亮**（约 192 种语言，浅/深色自动切主题）。
- **富输入**：多行输入框（`Enter` 发送 / `Shift+Enter` 换行），支持 **⌘V 粘贴文字 / 图片 / 文件**、拖拽图片与文件、「附图 / 附文件」按钮。
- **斜杠命令**：agent 广播命令时，输入 `/` 弹出命令联想，选中补全后按普通提示发送。
- 弹窗尺寸可用右下角**拖拽手柄**调整，并记住上次大小。

> 目前只接 **Hermes**（本地或远程）。未连接时点「设置」进入「Hermes 设置」窗口，详见 [接入 Hermes](#接入-hermes)。

### 右键：菜单

- **趋势图**：顶部内嵌最近 5 分钟消耗折线，每个客户端一条彩色折线，底部图例显示小计，顶部一行统计**当前速率 / 合计 / 峰值**。
- **Hermes**：本地 / 远程(SSH) 切换，「设置…」，「断开 Agent」。
- **动画**：选择动画包；子菜单底部含「重新扫描动画目录」「打开动画目录」。
- **速率口径**：加权 token / 全部 token / 仅 input+output / 金额（USD，models.dev 定价）。
- **尺寸**：16 / 18 / 20 / 22 / 24 pt。
- **最大帧率**：10 / 20 / 30 / 40 fps。
- **灵敏度**：0.25× ~ 4×。
- **数据源**：逐个开关采集源（含「模拟数据」，用于演示动画）。
- **重载模型定价 / 重置统计 / 开机自启**（自启仅 `.app` / `.exe` 形态可用）。

### Windows 差异

- **左键**打开状态窗口，而非 Chat。
- 右键菜单提供速率口径 / 尺寸 / 最大帧率 / 灵敏度 / 数据源 / 重载定价 / 重置统计 / 开机自启 / 退出。
- 暂无 Chat 与趋势图。

## 自定义动画包

把 PNG 序列放进 `~/Library/Application Support/TokCat/Animations/<id>/`，并附 `manifest.json`：

```json
{
  "id": "cat-hd",
  "displayName": "Cat HD",
  "frames": ["00.png", "01.png", "02.png"],
  "idleFPS": 2,
  "maxFPS": 40,
  "supportsColor": false
}
```

菜单「动画 → 重新扫描动画目录」即可加载。单色素材会自动用模板图渲染，适配浅/深色菜单栏。

## 接入 Hermes

Chat 使用 [Agent Client Protocol](https://agentclientprotocol.com)：TokCat 作为 **Client**，以子进程方式启动 Hermes 并按行分隔 JSON-RPC 2.0 通信。支持本地与远程两种模式。

### 本地

- 右键菜单「Hermes → 本地」，或用「设置…」里的本地区：一键安装 / 登录 / 文档 / 重新检测。
- 安装：`curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash`；登录：`hermes acp --setup`。

### 远程（SSH）

无需暴露端口，直接把远端的 `hermes acp` 的 stdio 通过 SSH 转到本地：

```
ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    [-p <port>] [-i <identity>] <target> "<remote command>"
```

「设置…」里可配：

| 字段 | 说明 |
|---|---|
| SSH 目标 | `user@host` 或 `~/.ssh/config` 别名（如 `be-tools`） |
| 端口 / 私钥 | 留空用默认；建议显式填私钥（GUI 可能没有 `SSH_AUTH_SOCK`） |
| 远程命令 | 默认 `hermes acp` |
| 登录 shell 包装 | 非交互 SSH 的 PATH 不含 hermes 时填，如 `bash -lc` / `zsh -lic` |
| 远程工作目录 | 传给 `session/new` 的远端 cwd；留空 = 远端 home |

「测试连接」会运行 `ssh <目标> "hermes acp --check"` 验证网络与 PATH。

## 已知边界

- 趋势历史仅在内存中保留最近 5 分钟，重启后清空。
- 金额口径依赖本地定价快照，不联网。
- 采集器对日志格式变化采取「无法识别则跳过」的容错策略。
- Chat 仅对接实现 ACP 的 **Hermes**（本地或远程 SSH）。
- 未配置推理 provider 时，agent 的 `session/new` 会失败；TokCat 会展示 agent 返回的错误，按提示完成登录即可。

## 许可

本项目以 **Apache-2.0** 发布，见 `LICENSE`。

内置的 `Cat (RunCat sprites)` 动画包复用自 [RunCat365](https://github.com/runcat-dev/RunCat365)（Apache-2.0）。详见 `THIRD_PARTY_NOTICES.md`。
