import XCTest
@testable import TokCatAgent

final class AgentDetectorTests: XCTestCase {
    #if canImport(Darwin)
    func testResolveAbsoluteAndPathLookup() {
        XCTAssertEqual(ShellEnvironment.resolve("/bin/ls"), "/bin/ls")
        XCTAssertNil(ShellEnvironment.resolve("/nonexistent/nope"))
        XCTAssertNotNil(ShellEnvironment.resolve("ls"))
    }
    #endif

    func testHermesPreset() {
        XCTAssertEqual(AgentPreset.hermes.executable, "hermes")
        XCTAssertEqual(AgentPreset.hermes.arguments, ["acp"])
        XCTAssertEqual(AgentPreset.hermes.id, "hermes")
    }

    func testLocalStatusShape() {
        // 只验证返回的是两种合法状态之一（依赖本机是否装了 hermes）。
        switch AgentDetector.localStatus() {
        case let .ready(path):
            XCTAssertFalse(path.isEmpty)
        case .missing:
            break
        }
    }

    #if canImport(Darwin)
    func testRemoteLaunchConfiguration() {
        let remote = RemoteSSHConfig(target: "be-tools")
        let config = AgentDetector.remoteLaunchConfiguration(remote, localCWD: NSTemporaryDirectory())
        XCTAssertEqual(config?.executablePath, "/usr/bin/ssh")
        XCTAssertEqual(config?.arguments.last, "hermes acp")
        XCTAssertEqual(config?.sessionCWD, NSTemporaryDirectory())
    }
    #endif

    func testRemoteLaunchConfigurationRequiresTarget() {
        let remote = RemoteSSHConfig(target: "  ")
        XCTAssertNil(AgentDetector.remoteLaunchConfiguration(remote, localCWD: NSTemporaryDirectory()))
    }

    #if canImport(Darwin)
    func testLocalLaunchConfigurationCwd() {
        guard let config = AgentDetector.localLaunchConfiguration(cwd: "/tmp") else {
            return // 本机未装 hermes 时跳过
        }
        XCTAssertEqual(config.sessionCWD, "/tmp")
    }
    #endif
}
