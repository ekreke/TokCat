# TokCat

菜单栏里的猫，跑多快取决于你消耗 token 多快。灵感来自 [RunCat](https://github.com/Kyome22/RunCat_for_mac)，但驱动的不是 CPU 占用，而是本机各个 AI 编码 agent 的 **token 消耗速率**。

- 菜单栏只显示一只小猫，token 消耗越快，动画越快；空闲时慢慢走。
- 采集源可插拔：opencode / Claude Code / Codex / pi，以及可选的 cc-switch 聚合库。
- 动画可插拔：内置程序化小猫，并支持从目录加载 PNG 序列动画包。

## 运行

```bash
make run          # 开发模式直接运行（swift run，菜单栏出现猫）
make test         # 运行单元测试
make app          # 打包为 build/TokCat.app（无 Dock 图标，ad-hoc 签名）
make dump         # 一次性扫描所有采集源并打印统计（验证/排障）
```

> 菜单栏图标：启动后出现在屏幕右上角。左键点开菜单。

## 菜单

- **速率**：实时 token/s（或 $/s），以及本次运行累计与分类明细。
- **动画**：切换动画包（内置猫 / 外部包）。
- **速率口径**：
  - 加权 token（默认 `input×1 + output×1 + cacheRead×0.1 + cacheWrite×0.1 + reasoning×1`）
  - 全部 token
  - 仅 input + output
  - 金额（USD，按 models.dev 定价）
- **灵敏度**：0.25× ~ 4×。
- **数据源**：逐个开关采集源（含 `模拟数据`，用于演示动画）。
- **开机自启**：仅在 `.app` 形态下可用（`SMAppService`）。
- **重载模型定价 / 重新扫描动画目录 / 重置统计 / 退出**。

## 架构

```
Sources/
├─ TokCatCore/      纯逻辑，无 UI 依赖，可单测
│   ├─ Models/      TokenUsage, TokenSample, RateMetric, TokenWeights, ModelPricing
│   ├─ Rate/        RateCalculator（滑动窗口 + EMA）
│   ├─ Animation/   AnimationPack 协议, AnimationRegistry, BuiltinCatPack,
│   │               ImageSequenceAnimationPack
│   └─ Sources/     TokenSource 协议, RateAggregator
├─ TokCatSources/   各 agent 采集器
│   ├─ JSONLTokenSource（基类：目录增量读取 + 去重）
│   ├─ ClaudeCodeSource / CodexSource / PiSource
│   ├─ OpenCodeSource（SQLite 只读）
│   ├─ CcSwitchDBSource（可选聚合源）
│   ├─ ModelPricingStore（models.dev 定价）
│   └─ Support/     FileTail, DirectoryTailer, SourceStateStore, SQLiteRO, Parsing
└─ TokCatApp/       AppKit 壳
    ├─ AppDelegate, StatusItemController（菜单栏 + 动画循环）
    ├─ RateEngine（1s 轮询聚合）, Settings, Formatting, LoginItem, DumpCommand
```

### 数据流

```
TokenSource.poll() ──► RateAggregator.ingest() ──► RateCalculator.rate()  (1 Hz)
                                                        │
                                              AnimationSpeedMapper
                                                        │
                                    帧率 = idleFPS + (maxFPS-idleFPS)·log1p(rate·sensitivity)/log1p(saturation·sensitivity)
```

- 轮询周期 1 秒；动画循环 30 Hz，按当前速率计算帧间隔，仅在需要换帧时更新图标。
- 帧率上限 24 fps，空闲 4.5 fps，控制功耗。

## 采集源细节

增量读取借鉴 cc-switch 的 `session_log_sync`：每个文件持久化字节偏移，只消费以换行结束的完整行；文件轮转/截断时自动归零。状态存于
`~/Library/Application Support/TokCat/state.json`。

| 源 | 位置 | token 字段 | 说明 |
|---|---|---|---|
| opencode | `~/.local/share/opencode/opencode.db` | `message.data.tokens.*` | 只读轮询，reasoning 与 output 并列需累计 |
| Claude Code | `~/.claude/projects/**/*.jsonl` | `message.usage.*` | 按 `message.id` 去重 |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl` | `event_msg.token_count.info.last_token_usage` | 单请求增量；`input_tokens` 需扣除缓存命中；reasoning 是 output 子集 |
| pi | `~/.pi/agent/sessions/**/*.jsonl` | `message.usage.*` | 仅 assistant 消息 |
| cc-switch | `~/.cc-switch/cc-switch.db` | `proxy_request_logs` | 默认关闭（与其他源重复） |

> 数据库源首次轮询从“当前时刻”开始，不回填历史。`make dump` 会从零扫描全部历史用于验证。

## 动画包扩展

把 PNG 序列放进 `~/Library/Application Support/TokCat/Animations/<id>/`，并写 `manifest.json`：

```json
{
  "id": "cat-hd",
  "displayName": "Cat HD",
  "frames": ["00.png", "01.png", "02.png"],
  "idleFPS": 1.5,
  "maxFPS": 18
}
```

菜单「重新扫描动画目录」即可加载。帧图会按模板图（template）渲染，自动适配浅色/深色菜单栏。

## 模型定价（金额口径）

优先读取 cc-switch 同步的 models.dev 快照 `~/.cc-switch/model-pricing.json`，不存在时回退读取 `cc-switch.db` 的 `model_pricing` 表。模型名做了归一化（大小写、`-free`/`-latest`、日期后缀等）。未命中定价的模型按 0 计。菜单「重载模型定价」可刷新。

## 已知边界

- `FakeTokenSource`（模拟数据）与真实源共用同一套接口，默认关闭。
- 金额口径依赖本地定价快照，不联网。
- 设置目前以菜单形式提供；后续可替换为独立 SwiftUI 设置窗口。
- 采集器对日志格式变化采取“无法识别则跳过”的容错策略。
