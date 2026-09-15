import XCTest
@testable import TokCatAgent

final class ACPContentTests: XCTestCase {
    private func dict(_ block: ACPContentBlock) throws -> [String: Any] {
        let data = try JSONEncoder().encode(block)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTextBlockEncoding() throws {
        let d = try dict(.text("hello"))
        XCTAssertEqual(d["type"] as? String, "text")
        XCTAssertEqual(d["text"] as? String, "hello")
        XCTAssertNil(d["data"])
        XCTAssertNil(d["mimeType"])
        XCTAssertNil(d["resource"])
    }

    func testImageBlockEncoding() throws {
        let d = try dict(.image(mimeType: "image/png", data: "AAAA"))
        XCTAssertEqual(d["type"] as? String, "image")
        XCTAssertEqual(d["mimeType"] as? String, "image/png")
        XCTAssertEqual(d["data"] as? String, "AAAA")
        XCTAssertNil(d["text"])
    }

    func testEmbeddedResourceEncoding() throws {
        let d = try dict(.embeddedResource(uri: "file:///a.txt", mimeType: "text/plain", text: "hi"))
        XCTAssertEqual(d["type"] as? String, "resource")
        let resource = try XCTUnwrap(d["resource"] as? [String: Any])
        XCTAssertEqual(resource["uri"] as? String, "file:///a.txt")
        XCTAssertEqual(resource["text"] as? String, "hi")
    }

    func testResourceLinkEncoding() throws {
        let d = try dict(.resourceLink(uri: "file:///b.pdf", name: "b.pdf", mimeType: "application/pdf", size: 12))
        XCTAssertEqual(d["type"] as? String, "resource_link")
        XCTAssertEqual(d["name"] as? String, "b.pdf")
        XCTAssertEqual(d["size"] as? Int, 12)
    }

    func testPromptParamsCompilesMixedContent() throws {
        let params = ACPPromptParams(
            sessionId: "s1",
            prompt: [.text("hi"), .image(mimeType: "image/png", data: "AA")]
        )
        let json = try params.jsonValue()
        let prompt = try XCTUnwrap(json["prompt"]?.arrayValue)
        XCTAssertEqual(prompt.count, 2)
        XCTAssertEqual(prompt[0]["type"]?.stringValue, "text")
        XCTAssertEqual(prompt[1]["type"]?.stringValue, "image")
        XCTAssertEqual(json["sessionId"]?.stringValue, "s1")
    }

    func testAvailableCommandsParsing() throws {
        let json = """
        {"sessionId":"s","update":{"sessionUpdate":"available_commands_update","availableCommands":[
          {"name":"web","description":"Search the web","input":{"hint":"query"}},
          {"name":"test","description":"Run tests"}
        ]}}
        """
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let update = ACPSessionUpdateParams(json: value).update

        guard case let .availableCommands(commands) = update else {
            return XCTFail("expected availableCommands")
        }
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0].name, "web")
        XCTAssertEqual(commands[0].description, "Search the web")
        XCTAssertEqual(commands[0].inputHint, "query")
        XCTAssertEqual(commands[1].name, "test")
        XCTAssertNil(commands[1].inputHint)
        XCTAssertEqual(update.agentEvent, .availableCommands(commands))
    }

    func testPromptCapabilitiesDecoding() throws {
        let json = """
        {"protocolVersion":1,"agentCapabilities":{"promptCapabilities":{"image":true,"embeddedContext":true}}}
        """
        let result = try JSONDecoder().decode(ACPInitializeResult.self, from: Data(json.utf8))
        let caps = result.agentCapabilities?.promptCapabilities
        XCTAssertEqual(caps?.image, true)
        XCTAssertEqual(caps?.embeddedContext, true)
        XCTAssertNil(caps?.audio)
    }
}
