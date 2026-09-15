import Foundation
import TokCatCore
import TokCatSources
import TokCatAgent
import TokCatEngine

/// TokCat 常驻 CLI。
///
/// 用法：
///   TokCatCli serve     常驻；stdin 收 JSON-Lines 命令，stdout 发 JSON-Lines 事件
///   TokCatCli dump      一次性扫描本机所有采集源并打印统计
///   TokCatCli version   打印版本
///
/// `serve` 协议（每行一个 JSON）：
///   命令：{"id":1,"cmd":"start|stop|metric|source|reloadPricing|reset|sources|quit","params":{...}}
///   响应：{"id":1,"ok":true}
///   事件：{"event":"ready"|"snapshot"|"error", ...}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "serve"

switch command {
case "serve":
    runServe()
case "dump":
    runDump()
case "version", "--version", "-v":
    print("TokCatCli \(TokCatVersion.string)")
default:
    FileHandle.standardError.write(Data("未知命令: \(command)\n用法: TokCatCli [serve|dump|version]\n".utf8))
    exit(2)
}

enum TokCatVersion {
    static var string: String { TokCatBuildVersion.string }
}

// MARK: - 协议输出

let stdoutLock = NSLock()

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    var line = data
    line.append(0x0A)
    stdoutLock.lock()
    FileHandle.standardOutput.write(line)
    stdoutLock.unlock()
}

func emitOK(_ id: Any?) {
    emit(["id": id ?? NSNull(), "ok": true])
}

func emitError(_ id: Any?, _ message: String) {
    emit(["id": id ?? NSNull(), "ok": false, "error": message])
}

func snapshotEvent(_ snapshot: RateSnapshot, session: ServeSession) -> [String: Any] {
    [
        "event": "snapshot",
        "rate": snapshot.rate,
        "totalUnits": snapshot.totalUnits,
        "currency": snapshot.unitIsCurrency,
        "windowSeconds": snapshot.windowSeconds,
        "sources": session.sourceStates(),
    ]
}

// MARK: - serve

final class ServeSession {
    private let store: SourceStateStore
    private var pricing: ModelPricingTable
    private var metricID: String
    private let engine: RateEngine

    init(metric: String = "weighted", window: TimeInterval = 15) {
        self.store = SourceStateStore()
        self.pricing = ModelPricingStore.loadDefault()
        self.metricID = metric
        let sources = SourceFactory.makeDefault(store: store)
        self.engine = RateEngine(
            sources: sources,
            converter: ServeSession.makeConverter(metric: metric, pricing: pricing),
            window: window,
            stateStore: store
        )
    }

    func onSnapshot(_ handler: @escaping (RateSnapshot) -> Void) { engine.onUpdate = handler }
    func start() { engine.start() }
    func stop() { engine.stop() }
    func reset() { engine.resetTotals() }

    func setMetric(_ id: String) {
        metricID = id
        engine.updateConverter(ServeSession.makeConverter(metric: id, pricing: pricing))
    }

    func setSource(id: String, enabled: Bool) {
        engine.allSources.first { $0.id == id }?.isEnabled = enabled
    }

    func reloadPricing() {
        pricing = ModelPricingStore.loadDefault()
        engine.updateConverter(ServeSession.makeConverter(metric: metricID, pricing: pricing))
    }

    func sourceStates() -> [[String: Any]] {
        engine.allSources.map {
            ["id": $0.id, "name": $0.displayName, "enabled": $0.isEnabled]
        }
    }

    static func makeConverter(metric: String, pricing: ModelPricingTable) -> TokenUnitConverter {
        let m: RateMetric
        switch metric {
        case "total": m = .total
        case "inputOutput": m = .inputOutput
        case "cost": m = .cost
        default: m = .weighted(.default)
        }
        return TokenUnitConverter(metric: m, pricing: pricing)
    }
}

func runServe() {
    let session = ServeSession()
    session.onSnapshot { snapshot in
        emit(snapshotEvent(snapshot, session: session))
    }
    session.start()
    emit(["event": "ready", "sources": session.sourceStates(), "version": TokCatVersion.string])

    DispatchQueue(label: "tokcat.cli.stdin").async {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            handleCommand(trimmed, session: session)
        }
        // stdin 关闭：退出。
        session.stop()
        exit(0)
    }

    dispatchMain()
}

func handleCommand(_ line: String, session: ServeSession) {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        emit(["event": "error", "message": "invalid json"])
        return
    }
    let id = object["id"]
    let cmd = object["cmd"] as? String ?? ""
    let params = object["params"] as? [String: Any] ?? [:]

    switch cmd {
    case "start":
        session.start(); emitOK(id)
    case "stop":
        session.stop(); emitOK(id)
    case "metric":
        session.setMetric(params["metric"] as? String ?? "weighted"); emitOK(id)
    case "source":
        session.setSource(id: params["id"] as? String ?? "", enabled: (params["enabled"] as? Bool) ?? true); emitOK(id)
    case "reloadPricing":
        session.reloadPricing(); emitOK(id)
    case "reset":
        session.reset(); emitOK(id)
    case "sources":
        emit(["id": id ?? NSNull(), "ok": true, "sources": session.sourceStates()])
    case "quit":
        session.stop(); exit(0)
    default:
        emitError(id, "unknown cmd: \(cmd)")
    }
}

// MARK: - dump

/// 一次性扫描所有采集源并打印统计，用于验证解析与路径解析是否正常。
func runDump() {
    let statePath = FileManager.default.temporaryDirectory
        .appendingPathComponent("tokcat-dump-\(UUID().uuidString).json")
    let store = SourceStateStore(url: statePath)
    defer { try? FileManager.default.removeItem(at: statePath) }

    print("app support: \(PlatformPaths.tokCatSupport.path)")
    print("home: \(PlatformPaths.home.path)")

    let sources: [TokenSource] = [
        OpenCodeSource(startFromNow: false),
        ClaudeCodeSource(store: store),
        CodexSource(store: store),
        PiSource(store: store),
        HermesSource(startFromNow: false),
        CcSwitchDBSource(startFromNow: false),
    ]

    let pricing = ModelPricingStore.loadDefault()
    print("model pricing loaded: \(pricing.models.count) models")

    for source in sources {
        var count = 0
        var total = 0
        var usage = TokenUsage.zero
        var lastModel: String?
        var firstAt: Date?
        var lastAt: Date?
        for _ in 0..<200 {
            let samples = source.poll(now: Date())
            if samples.isEmpty { break }
            count += samples.count
            for sample in samples {
                total += sample.usage.total
                usage += sample.usage
                if sample.model != nil { lastModel = sample.model }
                firstAt = firstAt ?? sample.at
                if lastAt == nil || sample.at > lastAt! { lastAt = sample.at }
            }
        }
        let span = (firstAt != nil && lastAt != nil) ? lastAt!.timeIntervalSince(firstAt!) : 0
        print("""
        [\(source.id)] samples=\(count) total=\(total) \
        in=\(usage.input) out=\(usage.output) cacheR=\(usage.cacheRead) cacheW=\(usage.cacheWrite) reason=\(usage.reasoning) \
        span=\(Int(span))s model=\(lastModel ?? "-")
        """)
    }
}
