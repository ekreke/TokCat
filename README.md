# TokCat

菜单栏里的猫，跑多快取决于你消耗 token 多快。灵感来自 [RunCat](https://github.com/runcat-dev/RunCat365)，但驱动的不是 CPU 占用，而是本机各个 AI 编码 agent 的 **token 消耗速率**。

- 菜单栏只显示一只小猫，token 消耗越快，动画越快；空闲时以 2fps 慢走。
- **左键点图标**：弹出 **Chat** —— 通过 [ACP (Agent Client Protocol)](https://agentclientprotocol.com) 与本地 agent 单次会话，流式回答、可多轮追问（只显示最新回答）。
- **右键点图标**：弹出菜单，顶部内嵌「最近 1 / 5 / 10 分钟」消耗趋势图。
- 采集源可插拔：opencode / Claude Code / Codex / pi，以及可选的 cc-switch 聚合库。
- Agent 可插拔：内置 Hermes / OpenCode / Gemini CLI 预设 + 自定义 ACP 命令，支持**检测与一键安装**。
- 动画可插拔：内置 RunCat 精灵图 + 外部 PNG 序列动画包。

## 运行

```bash
make run        # 开发模式直接运行（swift run，菜单栏出现猫）
make test       # 运行单元测试
make app        # 打包为 build/TokCat.app（无 Dock 图标，ad-hoc 签名）
make dump       # 一次性扫描所有采集源并打印统计（验证/排障）
```

## Chat（左键）

- 通过 **ACP** 与本地 agent 通信：`initialize` → `session/new` → `session/prompt`，流式接收 `session/update`（正文 / 思考 / 工具 / 计划）。
- **单次会话**：打开弹窗即启动一个会话，关闭弹窗即结束进程；弹窗内可多轮追问，**只显示最新回答**。
- 危险命令会弹出**授权条**（允许一次 / 允许会话 / 拒绝），对应 ACP 的 `session/request_permission`。
- 未安装 agent 时展示失败提示，点「设置」进入「Agent 检测 / 一键安装」窗口。

## 趋势图（右键菜单顶部）

- **每个客户端一条彩色折线**（opencode 蓝 / claude 橙 / codex 紫 / pi 青 / cc-switch 粉 / 模拟 灰，其它按 id 派生色），底部图例显示各客户端在所选范围内的小计。
- 时间范围通过菜单项「趋势范围」切换：**1 / 5 / 10 分钟**（记住上次选择）。
- 单位缩写用 `t`（如 `1.23K t/s`、`1.23K t`）；金额口径为 `$/s`、`$`。
- 数据按秒记录（窗口 600s）；图表按范围降采样（≤~120 点/条）保证流畅，统计仍按 1 秒。
- 随全局「速率口径」设置变化（加权 / 全部 / 仅 input+output / 金额）。

## 菜单（右键）

- **趋势图 + 趋势范围**：顶部内嵌最近消耗折线。
- **Agent**：选择预设（Hermes / OpenCode / Gemini CLI / 自定义命令），或打开「安装 / 重新检测…」。
- **动画**：选择动画包；子菜单底部含「重新扫描动画目录」「打开动画目录」。
- **速率口径**：加权 token / 全部 token / 仅 input+output / 金额（USD，models.dev 定价）。
- **尺寸**：16 / 18 / 20 / 22 / 24 pt。
- **最大帧率**：10 / 20 / 30 / 40 fps（对齐 RunCat 的上限设置）。
- **灵敏度**：0.25× ~ 4×。
- **数据源**：逐个开关采集源（含 `模拟数据`，用于演示动画）。
- **重载模型定价 / 重置统计 / 开机自启**（自启仅 `.app` 形态可用）。

## 架构

```
Sources/
├─ TokCatCore/      纯逻辑，无 UI 依赖，可单测
│   ├─ Models/      TokenUsage, TokenSample, RateMetric, TokenWeights, ModelPricing
│   ├─ Rate/        RateCalculator（滑动窗口 + EMA）, RateHistory（按秒环形缓冲）
│   ├─ Animation/   AnimationPack 协议, AnimationRegistry, AnimationSpeedMapper,
│   │               ImageSequenceAnimationPack, PixelScaling（最近邻缩放）
│   └─ Sources/     TokenSource 协议, RateAggregator
├─ TokCatSources/   各 agent 采集器
│   ├─ JSONLTokenSource（基类：目录增量读取 + 去重）
│   ├─ ClaudeCodeSource / CodexSource / PiSource
│   ├─ OpenCodeSource（SQLite 只读，按消息增量）
│   ├─ CcSwitchDBSource（可选聚合源）
│   ├─ ModelPricingStore（models.dev 定价）
│   └─ Support/     FileTail(POSIX stat), DirectoryTailer(带缓存), SourceStateStore, SQLiteRO, Parsing
├─ TokCatAgent/     ACP 客户端（纯逻辑，可单测）
│   ├─ JSONValue / JSONRPC（行分隔 JSON-RPC 2.0 编解码）
│   ├─ ACPMessages / AgentEvent（ACP 消息与 UI 事件模型）
│   ├─ ACPClient（子进程 + stdio，initialize/session/prompt/cancel/permission）
│   ├─ AgentPreset（内置预设 + 自定义命令解析）
│   ├─ AgentDetector（登入 shell PATH 解析 + 可执行文件检测）
│   └─ ShellRunner（流式执行安装命令）
└─ TokCatApp/       AppKit 壳
    ├─ AppDelegate, StatusItemController（状态栏 + 动画循环 + 左/右键交互）
    ├─ RateEngine（后台轮询聚合）, Settings, Formatting, LoginItem
    ├─ ChatSessionModel / ChatPopoverController / ChatView（左键 Chat）
    ├─ TrendView（右键菜单顶部内嵌的 Swift Charts 趋势图）
    ├─ AgentSetupModel / AgentSetupView / AgentSetupController（检测 + 一键安装）
    ├─ BundledAnimations（加载打包素材）, DumpCommand
    └─ Resources/RunCatCat/（RunCat365 猫精灵，Apache-2.0）
```

### 数据流

```
(后台串行队列)                        (主线程)
TokenSource.poll() ─► RateAggregator ─► RateCalculator (1 Hz)
                          │                    │
                          └─► RateHistory ─────┼─► 右键菜单趋势图（Swift Charts）
                                               │
                                     AnimationSpeedMapper（线性）
                                               │
                          fps = idle + (maxFPS - idle) × clamp(rate×sensitivity / saturationRate, 0, 1)
```

### 流畅度设计

- **采集全部在后台串行队列**（目录遍历、文件读取、SQLite、JSON 解析），算完回主线程更新 UI，避免阻塞动画。
- **帧号基于墙钟**：速率变化时重设基准，`frame = base + floor((now-base)/interval)`，主线程偶发阻塞后直接跳到正确帧，不会累积滞后或量化抖动。
- 动画 tick 60Hz，仅在帧号变化时更新图标；空闲 2fps、上限可配 10/20/30/40 fps。
- 文件增量读取用 POSIX `stat`（比 `FileManager.attributesOfItem` 便宜），目录列表每 5 秒重建一次。
- opencode 采集：用 db/wal 文件指纹做门控（空闲时几乎零查询），按 `rowid` 尾部窗口扫描，并按消息 id 只上报**增量**（因为 opencode 会在插入后继续更新行）。

## 动画与渲染

- **像素级缩放**：`PixelScaling.nearestNeighbor` 保证像素风素材硬边不糊。
- **外部动画包**：把 PNG 序列放进 `~/Library/Application Support/TokCat/Animations/<id>/`，附 `manifest.json`：

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

- 菜单「动画 → 重新扫描动画目录」即可加载。单色素材会自动用模板图渲染，适配浅/深菜单栏。

## Agent 接入（ACP）

左键 Chat 使用 [Agent Client Protocol](https://agentclientprotocol.com)：TokCat 作为 **Client**，
以子进程方式启动 agent 并按行分隔 JSON-RPC 2.0 通信。内置预设（右键菜单「Agent」）：

| 预设 | 启动命令 | 一键安装 | 登录 |
|---|---|---|---|
| Hermes | `hermes acp` | `curl -fsSL https://hermes-agent.nousresearch.com/install.sh \| bash` | `hermes acp --setup` |
| OpenCode | `opencode acp` | `brew install anomalyco/tap/opencode` | `opencode auth login` |
| Gemini CLI | `gemini --acp` | `brew install gemini-cli` | `gemini` |
| 自定义 | 用户填写 | — | — |

- **检测**：GUI 应用 PATH 极简，TokCat 用登入 shell（`zsh -lic`）解析真实 PATH，再在候选目录里查找可执行文件。
- **一键安装 / 检测窗口**：右键菜单「Agent → 安装 / 重新检测…」，安装命令实时输出日志，装完自动重新检测。
- 客户端**不声明** fs / terminal 能力，agent 使用自带工具；仅处理 `session/request_permission`（危险命令授权）。
- 默认工作目录为主目录，可在设置中调整；自定义命令保存在 UserDefaults。
- 门控集成测试：`TOKCAT_HERMES_IT=1 swift test` 会用真实 hermes 跑握手与 prompt 往返。

### 让 Hermes 使用自定义 OpenAI 兼容端点（示例：power）

编辑 `~/.hermes/config.yaml`：

```yaml
model:
  default: deepseek-v4.1-flash
  provider: power
  base_url: http://power.acme.red/v1
  api_key: sk-...
providers:
  power:
    base_url: http://power.acme.red/v1
    api_key: sk-...
    api_mode: chat_completions
    model: deepseek-v4.1-flash
```

## 采集源细节

增量读取借鉴 cc-switch 的 `session_log_sync`：每个文件持久化字节偏移，只消费以换行结束的完整行；文件轮转/截断时自动归零。状态存于
`~/Library/Application Support/TokCat/state.json`。

| 源 | 位置 | token 字段 | 说明 |
|---|---|---|---|
| opencode | `~/.local/share/opencode/opencode.db` | `message.data.tokens.*` | 只读；按 `rowid` 窗口 + 消息 id 增量，reasoning 与 output 并列需累计 |
| Claude Code | `~/.claude/projects/**/*.jsonl` | `message.usage.*` | 按 `message.id` 去重 |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl` | `event_msg.token_count.info.last_token_usage` | 单请求增量；`input_tokens` 需扣除缓存命中；reasoning 是 output 子集 |
| pi | `~/.pi/agent/sessions/**/*.jsonl` | `message.usage.*` | 仅 assistant 消息 |
| cc-switch | `~/.cc-switch/cc-switch.db` | `proxy_request_logs` | 默认关闭（与其他源重复） |

> 数据库源首次轮询从"当前时刻"开始，不回填历史。`make dump` 会从零扫描全部历史用于验证。

## 模型定价（金额口径）

优先读取 cc-switch 同步的 models.dev 快照 `~/.cc-switch/model-pricing.json`，不存在时回退读取 `cc-switch.db` 的 `model_pricing` 表。模型名做了归一化（大小写、`-free`/`-latest`、日期后缀等）。未命中定价的模型按 0 计。菜单「重载模型定价」可刷新。

## 许可

本项目以 **Apache-2.0** 发布，见 `LICENSE`。

内置的 `Cat (RunCat sprites)` 动画包复用自
[RunCat365](https://github.com/runcat-dev/RunCat365)（Apache-2.0），原样复制自
`RunCat365/resources/runners/cat/`。详见 `THIRD_PARTY_NOTICES.md`。

## 已知边界

- 「模拟数据」源与真实源共用同一套接口，默认关闭。
- 趋势历史仅在内存中保留最近 5 分钟，重启后清空。
- 金额口径依赖本地定价快照，不联网。
- 设置目前以菜单形式提供；后续可替换为独立 SwiftUI 设置窗口。
- 采集器对日志格式变化采取“无法识别则跳过”的容错策略。
- Chat 仅对接实现 ACP 的 agent；Claude Code / Codex / Pi 需先安装各自的 ACP adapter（可填入「自定义命令」）。
- 未配置推理 provider 时，agent 的 `session/new` 会失败；TokCat 会展示 agent 返回的错误，按提示完成登录即可。
