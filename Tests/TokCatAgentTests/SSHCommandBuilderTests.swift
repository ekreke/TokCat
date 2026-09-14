import XCTest
@testable import TokCatAgent

final class SSHCommandBuilderTests: XCTestCase {
    func testBasicArguments() {
        let config = RemoteSSHConfig(target: "be-tools", identityFile: nil, remoteCommand: "hermes acp")
        XCTAssertEqual(SSHCommandBuilder.arguments(config, command: "hermes acp"), [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "be-tools",
            "hermes acp",
        ])
    }

    #if canImport(Darwin)
    func testPortAndIdentityFile() {
        let config = RemoteSSHConfig(target: "root@10.0.0.1", port: 2222, identityFile: "~/.ssh/id_ed25519")
        let args = SSHCommandBuilder.arguments(config, command: "hermes acp")
        XCTAssertTrue(args.contains("-p"))
        XCTAssertTrue(args.contains("2222"))
        XCTAssertTrue(args.contains("-i"))
        // 私钥路径会把 ~ 展开成 home。
        XCTAssertTrue(args.contains("\(NSHomeDirectory())/.ssh/id_ed25519"))
        XCTAssertEqual(args.last, "hermes acp")
    }
    #endif

    func testLoginShellWrapping() {
        let config = RemoteSSHConfig(target: "h", identityFile: nil, remoteCommand: "hermes acp", loginShell: "zsh -lic")
        XCTAssertEqual(SSHCommandBuilder.effectiveRemoteCommand(config, command: "hermes acp"), "zsh -lic 'hermes acp'")

        let bare = RemoteSSHConfig(target: "h", identityFile: nil, remoteCommand: "hermes acp", loginShell: "")
        XCTAssertEqual(SSHCommandBuilder.effectiveRemoteCommand(bare, command: "hermes acp"), "hermes acp")
    }

    func testCheckCommand() {
        let config = RemoteSSHConfig(target: "h", identityFile: nil, remoteCommand: "hermes acp")
        XCTAssertEqual(SSHCommandBuilder.checkCommand(config), "hermes acp --check")
    }

    func testSingleQuoteEscaping() {
        XCTAssertEqual(SSHCommandBuilder.singleQuote("a'b"), "'a'\\''b'")
        XCTAssertEqual(SSHCommandBuilder.singleQuote("plain"), "'plain'")
    }

    #if canImport(Darwin)
    func testShellCommandContainsQuotedSsh() {
        let config = RemoteSSHConfig(target: "be-tools", identityFile: nil, remoteCommand: "hermes acp")
        let command = SSHCommandBuilder.shellCommand(config, command: "hermes acp --check")
        XCTAssertTrue(command.hasPrefix("'/usr/bin/ssh'"))
        XCTAssertTrue(command.contains("'be-tools'"))
        XCTAssertTrue(command.contains("'hermes acp --check'"))
    }
    #endif
}
