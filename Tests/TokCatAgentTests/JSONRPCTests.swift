import XCTest
@testable import TokCatAgent

final class JSONRPCTests: XCTestCase {
    private func decode(_ json: String) throws -> InboundMessage {
        try JSONRPCCodec.decode(line: Data(json.utf8))
    }

    func testEncodeRequestRoundTrip() throws {
        let params = ACPPromptParams(sessionId: "s1", prompt: [.text("你好")])
        let request = JSONRPCRequest(id: 7, method: ACPMethod.sessionPrompt, params: try params.jsonValue())
        let line = try JSONRPCCodec.encode(request)

        let message = try decode(String(decoding: line, as: UTF8.self))
        guard case let .request(decoded) = message else {
            return XCTFail("应为请求，实际 \(message)")
        }
        XCTAssertEqual(decoded.id, 7)
        XCTAssertEqual(decoded.method, "session/prompt")
        let decodedParams = try decoded.params.decode(ACPPromptParams.self)
        XCTAssertEqual(decodedParams.sessionId, "s1")
        XCTAssertEqual(decodedParams.prompt.first?.text, "你好")
    }

    func testDecodeNotification() throws {
        let json = """
        {"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"hi"}}}}
        """
        guard case let .notification(note) = try decode(json) else {
            return XCTFail("应为通知")
        }
        XCTAssertEqual(note.method, "session/update")
        XCTAssertEqual(note.params["sessionId"]?.stringValue, "s1")
    }

    func testDecodeResponse() throws {
        let json = #"{"jsonrpc":"2.0","id":3,"result":{"sessionId":"abc"}}"#
        guard case let .response(response) = try decode(json) else {
            return XCTFail("应为响应")
        }
        XCTAssertEqual(response.id, 3)
        XCTAssertEqual(response.result["sessionId"]?.stringValue, "abc")
    }

    func testDecodeStringIDAndError() throws {
        let json = #"{"jsonrpc":"2.0","id":"x","error":{"code":-32601,"message":"unknown"}}"#
        guard case let .error(response) = try decode(json) else {
            return XCTFail("应为错误响应")
        }
        XCTAssertEqual(response.id, "x")
        XCTAssertEqual(response.error.code, JSONRPCError.methodNotFound)
        XCTAssertEqual(response.error.message, "unknown")
    }

    func testDecodeRejectsNonJSONRPC() {
        XCTAssertThrowsError(try decode(#"{"id":1,"result":{}}"#))
        XCTAssertThrowsError(try decode("not json"))
    }

    func testRequestWithoutParamsOmitsField() throws {
        let request = JSONRPCRequest(id: 1, method: "custom/noop")
        let line = try JSONRPCCodec.encode(request)
        XCTAssertFalse(String(decoding: line, as: UTF8.self).contains("params"))
    }
}
