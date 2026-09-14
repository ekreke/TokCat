import XCTest
@testable import TokCatAgent

final class AgentDetectorTests: XCTestCase {
    func testResolveAbsoluteAndPathLookup() {
        XCTAssertEqual(ShellEnvironment.resolve("/bin/ls"), "/bin/ls")
        XCTAssertNil(ShellEnvironment.resolve("/nonexistent/nope"))
        XCTAssertNotNil(ShellEnvironment.resolve("ls"))
    }

    func testParseCustomCommandWithQuotes() {
        let parsed = AgentPreset.parseCustomCommand("npx --yes \"@zed-industries/claude-agent-acp\"")
        XCTAssertEqual(parsed?.executable, "npx")
        XCTAssertEqual(parsed?.arguments, ["--yes", "@zed-industries/claude-agent-acp"])
        XCTAssertNil(AgentPreset.parseCustomCommand("   "))
    }

    func testBuiltinPresetLookup() {
        XCTAssertEqual(AgentPreset.builtin(id: "hermes")?.arguments, ["acp"])
        XCTAssertEqual(AgentPreset.builtin(id: "gemini")?.arguments, ["--acp"])
        XCTAssertNil(AgentPreset.builtin(id: "does-not-exist"))
    }

    func testLaunchConfigurationForResolvableCustomCommand() throws {
        let configuration = AgentDetector.launchConfiguration(
            for: AgentPreset.builtin(id: AgentPreset.customID)!,
            customCommand: "/bin/echo hello",
            cwd: NSTemporaryDirectory()
        )
        XCTAssertEqual(configuration?.executablePath, "/bin/echo")
        XCTAssertEqual(configuration?.arguments, ["hello"])
        XCTAssertNotNil(configuration?.environment?["PATH"])
    }

    func testLaunchConfigurationMissingBinary() {
        let configuration = AgentDetector.launchConfiguration(
            for: AgentPreset.builtin(id: AgentPreset.customID)!,
            customCommand: "/definitely/not/here acp",
            cwd: NSTemporaryDirectory()
        )
        XCTAssertNil(configuration)
    }
}
