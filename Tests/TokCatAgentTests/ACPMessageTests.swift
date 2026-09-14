import XCTest
@testable import TokCatAgent

final class ACPMessageTests: XCTestCase {
    private func value(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testParseAgentMessageChunk() throws {
        let json = try value(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hello"}}"#)
        XCTAssertEqual(ACPSessionUpdate(json: json), .agentMessageChunk(text: "Hello"))
        XCTAssertEqual(ACPSessionUpdate(json: json).agentEvent, .agentText("Hello"))
    }

    func testParseThoughtAndToolCall() throws {
        let thought = try value(#"{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"think"}}"#)
        XCTAssertEqual(ACPSessionUpdate(json: thought), .agentThoughtChunk(text: "think"))

        let tool = try value(#"{"sessionUpdate":"tool_call","toolCallId":"t1","title":"运行 bash","kind":"execute","status":"pending"}"#)
        XCTAssertEqual(ACPSessionUpdate(json: tool), .toolCall(id: "t1", title: "运行 bash", kind: "execute", status: "pending"))
        XCTAssertEqual(ACPSessionUpdate(json: tool).agentEvent, .toolCall(title: "运行 bash"))
    }

    func testParseToolCallUpdateAndPlan() throws {
        let update = try value(#"{"sessionUpdate":"tool_call_update","toolCallId":"t1","status":"completed"}"#)
        XCTAssertEqual(ACPSessionUpdate(json: update), .toolCallUpdate(id: "t1", title: nil, status: "completed"))

        let plan = try value(#"{"sessionUpdate":"plan","entries":[{"content":"a","status":"pending"},{"content":"b","status":"completed"}]}"#)
        XCTAssertEqual(ACPSessionUpdate(json: plan), .plan(entries: ["a", "b"]))
    }

    func testParseUnknownAndSessionUpdateParams() throws {
        XCTAssertEqual(ACPSessionUpdate(json: try value(#"{"sessionUpdate":"config_option_update"}"#)), .unknown(kind: "config_option_update"))
        XCTAssertNil(ACPSessionUpdate(json: try value(#"{"sessionUpdate":"usage_update"}"#)).agentEvent)

        let params = ACPSessionUpdateParams(json: try value(#"{"sessionId":"s9","update":{"sessionUpdate":"agent_message_chunk","content":{"text":"x"}}}"#))
        XCTAssertEqual(params.sessionId, "s9")
        XCTAssertEqual(params.update, .agentMessageChunk(text: "x"))
    }

    func testInitializeParamsEncoding() throws {
        let params = ACPInitializeParams(
            clientCapabilities: ACPClientCapabilities(fs: nil, terminal: nil),
            clientInfo: ACPImplementation(name: "TokCat", title: "TokCat", version: "0.1")
        )
        let json = try params.jsonValue()
        XCTAssertEqual(json["protocolVersion"]?.intValue, 1)
        XCTAssertEqual(json["clientInfo"]?["name"]?.stringValue, "TokCat")
        XCTAssertNotNil(json["clientCapabilities"])
        XCTAssertNil(json["clientCapabilities"]?["terminal"])
    }

    func testPermissionResultEncoding() throws {
        XCTAssertEqual(try ACPPermissionResult.selected("allow_once").jsonValue()["outcome"]?["optionId"]?.stringValue, "allow_once")
        XCTAssertEqual(try ACPPermissionResult.cancelled.jsonValue()["outcome"]?["outcome"]?.stringValue, "cancelled")
    }

    func testPermissionParamsDecoding() throws {
        let json = try value(#"{"sessionId":"s1","toolCall":{"toolCallId":"perm-1","title":"$ rm -rf /"},"options":[{"optionId":"allow_once","name":"Allow once","kind":"allow_once"},{"optionId":"deny","name":"Deny","kind":"reject_once"}]}"#)
        let params = try json.decode(ACPPermissionParams.self)
        XCTAssertEqual(params.sessionId, "s1")
        XCTAssertEqual(params.toolCall?.title, "$ rm -rf /")
        XCTAssertEqual(params.options.count, 2)
        XCTAssertEqual(params.options.first?.optionId, "allow_once")
    }
}
