import XCTest
@testable import TokCatAgent

/// 用 python mock agent 验证 ACPClient 的完整链路（真实子进程 + stdio）。
final class ACPClientIntegrationTests: XCTestCase {
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [AgentEvent] = []
        func append(_ event: AgentEvent) { lock.lock(); values.append(event); lock.unlock() }
        var events: [AgentEvent] { lock.lock(); defer { lock.unlock() }; return values }
    }

    private func makeClient(permission: ACPClient.PermissionHandler? = nil) throws -> (ACPClient, Collector) {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/mock_agent.py")
        let configuration = ACPLaunchConfiguration(
            executablePath: "/usr/bin/env",
            arguments: ["python3", script.path],
            cwd: NSTemporaryDirectory()
        )
        let client = ACPClient(configuration: configuration)
        let collector = Collector()
        client.onEvent = { collector.append($0) }
        client.permissionHandler = permission
        try client.launch()
        return (client, collector)
    }

    func testInitializeAndStreamingPrompt() async throws {
        let (client, collector) = try makeClient()
        defer { client.stop() }

        let initialized = try await client.initialize(clientInfo: ACPImplementation(name: "TokCat", version: "test"))
        XCTAssertEqual(initialized.protocolVersion, 1)
        XCTAssertEqual(initialized.agentInfo?.name, "mock-agent")

        let session = try await client.newSession(cwd: NSTemporaryDirectory())
        XCTAssertEqual(session.sessionId, "test-session")

        let result = try await client.prompt(sessionId: session.sessionId, text: "hi")
        XCTAssertEqual(result.stopReason, "end_turn")

        // 让主队列把流式事件派发完。
        await MainActor.run {}
        XCTAssertEqual(collector.events, [
            .agentText("Hello"),
            .agentThought("thinking"),
            .agentText(" world"),
        ])
    }

    func testPermissionRoundTrip() async throws {
        let (client, collector) = try makeClient(permission: { params in
            XCTAssertEqual(params.options.first?.optionId, "allow_once")
            return .selected("allow_once")
        })
        defer { client.stop() }

        _ = try await client.initialize(clientInfo: ACPImplementation(name: "TokCat", version: "test"))
        let session = try await client.newSession(cwd: NSTemporaryDirectory())
        _ = try await client.prompt(sessionId: session.sessionId, text: "需要 permission")

        await MainActor.run {}
        XCTAssertEqual(collector.events, [.agentText("chose:allow_once")])
    }

    func testPermissionDefaultsToCancelled() async throws {
        let (client, collector) = try makeClient(permission: nil)
        defer { client.stop() }

        _ = try await client.initialize(clientInfo: ACPImplementation(name: "TokCat", version: "test"))
        let session = try await client.newSession(cwd: NSTemporaryDirectory())
        _ = try await client.prompt(sessionId: session.sessionId, text: "permission please")

        await MainActor.run {}
        XCTAssertEqual(collector.events, [.agentText("chose:none")])
    }

    /// 真实 agent 握手验证；默认跳过，`TOKCAT_HERMES_IT=1 swift test` 时运行。
    func testRealHermesHandshake() async throws {
        guard ProcessInfo.processInfo.environment["TOKCAT_HERMES_IT"] == "1" else {
            throw XCTSkip("设置 TOKCAT_HERMES_IT=1 才运行真实 hermes 集成测试")
        }
        guard let configuration = AgentDetector.localLaunchConfiguration(cwd: NSTemporaryDirectory()) else {
            throw XCTSkip("未检测到 hermes 可执行文件")
        }
        let client = ACPClient(configuration: configuration)
        defer { client.stop() }

        try client.launch()
        let initialized = try await client.initialize(clientInfo: ACPImplementation(name: "TokCat", version: "test"))
        XCTAssertEqual(initialized.agentInfo?.name, "hermes-agent")

        do {
            let session = try await client.newSession(cwd: NSTemporaryDirectory())
            XCTAssertFalse(session.sessionId.isEmpty)
            client.cancel(sessionId: session.sessionId)
        } catch {
            // 本机 hermes 未配置 provider 时 session/new 会失败；这属于环境问题而非客户端问题。
            throw XCTSkip("hermes 未配置 provider：\(error.localizedDescription)")
        }
    }

    /// 真实 prompt 往返；默认跳过，`TOKCAT_HERMES_IT=1 swift test` 时运行。
    func testRealHermesPrompt() async throws {
        guard ProcessInfo.processInfo.environment["TOKCAT_HERMES_IT"] == "1" else {
            throw XCTSkip("设置 TOKCAT_HERMES_IT=1 才运行真实 hermes 集成测试")
        }
        guard let configuration = AgentDetector.localLaunchConfiguration(cwd: NSTemporaryDirectory()) else {
            throw XCTSkip("未检测到 hermes 可执行文件")
        }
        let client = ACPClient(configuration: configuration)
        let collector = Collector()
        client.onEvent = { collector.append($0) }
        defer { client.stop() }

        try client.launch()
        _ = try await client.initialize(clientInfo: ACPImplementation(name: "TokCat", version: "test"))
        let session = try await client.newSession(cwd: NSTemporaryDirectory())
        let result = try await client.prompt(sessionId: session.sessionId, text: "Reply with exactly one word: pong")
        await MainActor.run {}

        let texts = collector.events.compactMap { event -> String? in
            if case let .agentText(text) = event { return text }
            return nil
        }
        NSLog("TokCat IT events=\(collector.events) stopReason=\(result.stopReason ?? "nil")")
        XCTAssertFalse(texts.joined().isEmpty, "未收到任何回答文本")
    }

    func testLaunchFailureOnMissingExecutable() async throws {
        let client = ACPClient(configuration: ACPLaunchConfiguration(
            executablePath: "/nonexistent/agent-binary",
            arguments: [],
            cwd: NSTemporaryDirectory()
        ))
        XCTAssertThrowsError(try client.launch())
    }
}
