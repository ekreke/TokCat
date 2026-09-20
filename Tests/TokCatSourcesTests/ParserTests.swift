import XCTest
import TokCatCore
@testable import TokCatSources

final class ParserTests: XCTestCase {
    private var root: URL!
    private var store: SourceStateStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = SourceStateStore(url: root.appendingPathComponent("state.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ contents: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.data(using: .utf8)!.write(to: url)
    }

    // MARK: - Claude

    func testClaudeParsing() throws {
        let line = """
        {"timestamp":"2026-09-10T02:33:02.428Z","message":{"id":"msg_1","model":"glm-5.3","usage":{"input_tokens":32545,"cache_creation_input_tokens":10,"cache_read_input_tokens":64,"output_tokens":44}}}
        """
        try write(line + "\n", to: "proj/session.jsonl")

        let source = ClaudeCodeSource(store: store, root: root)
        let samples = source.poll(now: Date())
        let sample = try XCTUnwrap(samples.first)
        XCTAssertEqual(sample.usage.input, 32545)
        XCTAssertEqual(sample.usage.output, 44)
        XCTAssertEqual(sample.usage.cacheRead, 64)
        XCTAssertEqual(sample.usage.cacheWrite, 10)
        XCTAssertEqual(sample.model, "glm-5.3")
        XCTAssertEqual(sample.id, "msg_1")
    }

    func testClaudeDeduplicatesRepeatedRequestId() throws {
        let line = """
        {"timestamp":"2026-09-10T02:33:02.428Z","message":{"id":"msg_dup","model":"m","usage":{"input_tokens":100,"output_tokens":1}}}
        """
        try write((line + "\n" + line + "\n"), to: "a.jsonl")
        let source = ClaudeCodeSource(store: store, root: root)
        XCTAssertEqual(source.poll(now: Date()).count, 1)
    }

    // MARK: - Codex

    func testCodexParsingSplitsCachedInputAndTracksModel() throws {
        let turnContext = """
        {"timestamp":"2026-03-20T04:30:00.000Z","ordinal":1,"type":"event_msg","payload":{"type":"turn_context","model":"gpt-5.6-luna"}}
        """
        let tokenCount = """
        {"timestamp":"2026-03-20T04:34:38.049Z","ordinal":246,"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":85701,"cached_input_tokens":85504,"cache_write_input_tokens":0,"output_tokens":1903,"reasoning_output_tokens":1853,"total_tokens":87604},"total_token_usage":{"input_tokens":2448452,"output_tokens":9327}}}}
        """
        try write(turnContext + "\n" + tokenCount + "\n", to: "2026/03/20/rollout-x.jsonl")

        let source = CodexSource(store: store, root: root)
        let samples = source.poll(now: Date())
        let sample = try XCTUnwrap(samples.first)
        XCTAssertEqual(sample.usage.input, 85701 - 85504)
        XCTAssertEqual(sample.usage.cacheRead, 85504)
        XCTAssertEqual(sample.usage.output, 1903)
        XCTAssertEqual(sample.model, "gpt-5.6-luna")
        // reasoning 是 output 子集，不重复累计
        XCTAssertEqual(sample.usage.reasoning, 0)
    }

    func testCodexIgnoresNonTokenEvents() throws {
        let line = """
        {"timestamp":"2026-03-20T04:30:00.000Z","ordinal":1,"type":"event_msg","payload":{"type":"agent_message","message":"hi"}}
        """
        try write(line + "\n", to: "a.jsonl")
        let source = CodexSource(store: store, root: root)
        XCTAssertTrue(source.poll(now: Date()).isEmpty)
    }

    // MARK: - ZCode

    func testZCodeParsingSubtractsCacheReadAndTracksModel() throws {
        let networkStatus = """
        {"id":"ns-1","sessionId":"sess_1","type":"model_network_status","timestamp":"2026-08-27T05:07:18.355Z","payload":{"baseURL":"https://open.bigmodel.cn/api/anthropic","model":{"providerId":"builtin:bigmodel-coding-plan","modelId":"GLM-5.3","role":"main"}}}
        """
        let modelComplete = """
        {"id":"mc-1","sessionId":"sess_1","type":"model_complete","timestamp":"2026-08-27T05:07:22.638Z","payload":{"content":"","stopReason":"tool-calls","usage":{"inputTokens":5368,"outputTokens":210,"totalTokens":5578,"cacheReadTokens":3136,"cacheWriteTokens":0}}}
        """
        try write(networkStatus + "\n" + modelComplete + "\n", to: "sess_1/agent_1/transcript.jsonl")

        let source = ZCodeSource(store: store, root: root)
        let samples = source.poll(now: Date())
        let sample = try XCTUnwrap(samples.first)
        XCTAssertEqual(sample.sourceId, "zcode")
        XCTAssertEqual(sample.usage.input, 5368 - 3136)
        XCTAssertEqual(sample.usage.output, 210)
        XCTAssertEqual(sample.usage.cacheRead, 3136)
        XCTAssertEqual(sample.usage.cacheWrite, 0)
        XCTAssertEqual(sample.usage.reasoning, 0)
        XCTAssertEqual(sample.model, "GLM-5.3")
        // path 是绝对路径且分隔符随平台不同，只断言事件 id 部分
        XCTAssertTrue(sample.id.hasSuffix("#mc-1"))
    }

    func testZCodeHandlesReasoningTokensVariant() throws {
        // 真实日志中约 5% 的事件 usage 无 cacheWriteTokens、带 reasoningTokens
        let line = """
        {"id":"mc-3","sessionId":"sess_1","type":"model_complete","timestamp":"2026-08-27T05:07:22.638Z","payload":{"content":"","stopReason":"end_turn","usage":{"inputTokens":9000,"outputTokens":1500,"cacheReadTokens":3000,"reasoningTokens":1200,"totalTokens":10500}}}
        """
        try write(line + "\n", to: "a.jsonl")
        let source = ZCodeSource(store: store, root: root)
        let sample = try XCTUnwrap(source.poll(now: Date()).first)
        XCTAssertEqual(sample.usage.input, 9000 - 3000)
        XCTAssertEqual(sample.usage.output, 1500)
        XCTAssertEqual(sample.usage.cacheRead, 3000)
        // reasoning 是 output 子集，不重复累计
        XCTAssertEqual(sample.usage.reasoning, 0)
    }

    func testZCodeIgnoresNonCompleteEvents() throws {
        let streaming = """
        {"id":"ms-1","sessionId":"sess_1","type":"model_streaming","timestamp":"2026-08-27T05:07:20.595Z","payload":{"delta":"hi"}}
        """
        try write(streaming + "\n", to: "sess_1/agent_1/transcript.jsonl")
        let source = ZCodeSource(store: store, root: root)
        XCTAssertTrue(source.poll(now: Date()).isEmpty)
    }

    func testZCodeSkipsEmptyUsage() throws {
        let line = """
        {"id":"mc-2","sessionId":"sess_1","type":"model_complete","timestamp":"2026-08-27T05:07:22.638Z","payload":{"content":"","stopReason":"end_turn","usage":{"inputTokens":0,"outputTokens":0,"totalTokens":0,"cacheReadTokens":0,"cacheWriteTokens":0}}}
        """
        try write(line + "\n", to: "a.jsonl")
        let source = ZCodeSource(store: store, root: root)
        XCTAssertTrue(source.poll(now: Date()).isEmpty)
    }

    // MARK: - pi

    func testPiParsing() throws {
        let line = """
        {"type":"message","id":"3361d58c","timestamp":"2026-09-10T10:13:11.783Z","message":{"role":"assistant","provider":"ekreke-copy","model":"deepseek-v4.1-flash","usage":{"input":577,"output":2,"cacheRead":0,"cacheWrite":0,"reasoning":0,"totalTokens":579}}}
        """
        try write(line + "\n", to: "p/session.jsonl")
        let source = PiSource(store: store, root: root)
        let sample = try XCTUnwrap(source.poll(now: Date()).first)
        XCTAssertEqual(sample.usage.input, 577)
        XCTAssertEqual(sample.usage.output, 2)
        XCTAssertEqual(sample.model, "deepseek-v4.1-flash")
    }

    func testPiIgnoresUserMessages() throws {
        let line = """
        {"type":"message","id":"u1","timestamp":"2026-09-10T10:13:10.000Z","message":{"role":"user","content":[{"type":"text","text":"hi"}]}}
        """
        try write(line + "\n", to: "p/u.jsonl")
        let source = PiSource(store: store, root: root)
        XCTAssertTrue(source.poll(now: Date()).isEmpty)
    }

    // MARK: - 增量

    func testIncrementalPollOnlyReturnsNewLines() throws {
        try write("", to: "s.jsonl")
        let source = ClaudeCodeSource(store: store, root: root)
        XCTAssertTrue(source.poll(now: Date()).isEmpty)

        let line = """
        {"timestamp":"2026-09-10T02:33:02.428Z","message":{"id":"m2","model":"m","usage":{"input_tokens":5,"output_tokens":5}}}
        """
        try write(line + "\n", to: "s.jsonl")
        XCTAssertEqual(source.poll(now: Date()).count, 1)
        // 第二次轮询不应重复
        XCTAssertTrue(source.poll(now: Date()).isEmpty)
    }
}
