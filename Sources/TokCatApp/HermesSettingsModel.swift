import AppKit
import Foundation
import TokCatAgent

/// 「Hermes 设置」窗口的视图模型（本地 / 远程 SSH）。
///
/// 检测与 SSH 测试都会阻塞，统一放到后台线程执行。
final class HermesSettingsModel: ObservableObject, @unchecked Sendable {
    @Published var mode: HermesMode
    @Published var localWorkingDirectory: String
    @Published var sshTarget: String
    @Published var sshPortText: String
    @Published var sshIdentityFile: String
    @Published var remoteCommand: String
    @Published var remoteLoginShell: String
    @Published var remoteWorkingDirectory: String

    @Published private(set) var localPath: String?
    @Published private(set) var log: String = ""
    @Published private(set) var busy: Bool = false

    private let settings: AppSettings
    private let onChange: () -> Void

    init(settings: AppSettings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        self.mode = settings.hermesMode
        self.localWorkingDirectory = settings.agentWorkingDirectory
        self.sshTarget = settings.sshTarget
        self.sshPortText = settings.sshPort > 0 ? String(settings.sshPort) : ""
        self.sshIdentityFile = settings.sshIdentityFile
        self.remoteCommand = settings.remoteCommand
        self.remoteLoginShell = settings.remoteLoginShell
        self.remoteWorkingDirectory = settings.remoteWorkingDirectory
        refreshLocal()
    }

    // MARK: - 本地

    /// 后台检测本地 hermes。
    func refreshLocal() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            ShellEnvironment.invalidateCache()
            let status = AgentDetector.localStatus()
            let path: String?
            switch status {
            case let .ready(value): path = value
            case .missing: path = nil
            }
            DispatchQueue.main.async { self.localPath = path }
        }
    }

    func installLocal() {
        guard let command = AgentPreset.hermes.installCommand else { return }
        run(command: command, label: "安装 Hermes")
    }

    func openLocalLogin() {
        guard let command = AgentPreset.hermes.loginCommand else { return }
        openInTerminal(command: command)
    }

    func openLocalDocs() {
        guard let raw = AgentPreset.hermes.docsURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 远程

    /// 用当前表单值组装远程配置。
    var formRemoteConfig: RemoteSSHConfig {
        RemoteSSHConfig(
            target: sshTarget.trimmingCharacters(in: .whitespaces),
            port: Int(sshPortText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil },
            identityFile: sshIdentityFile.trimmingCharacters(in: .whitespaces).isEmpty ? nil : sshIdentityFile,
            remoteCommand: remoteCommand.trimmingCharacters(in: .whitespaces).isEmpty ? "hermes acp" : remoteCommand,
            loginShell: remoteLoginShell,
            remoteWorkingDirectory: remoteWorkingDirectory
        )
    }

    /// 运行 `ssh <target> "<remote command> --check"` 做连通性自检。
    func testRemoteConnection() {
        let config = formRemoteConfig
        guard config.isConfigured else {
            log += "\n[请先填写 SSH 目标]\n"
            return
        }
        let command = SSHCommandBuilder.shellCommand(config, command: SSHCommandBuilder.checkCommand(config))
        run(command: command, label: "测试连接")
    }

    // MARK: - 保存

    func save() {
        settings.hermesMode = mode
        settings.agentWorkingDirectory = localWorkingDirectory.trimmingCharacters(in: .whitespaces)
        settings.sshTarget = sshTarget.trimmingCharacters(in: .whitespaces)
        settings.sshPort = Int(sshPortText.trimmingCharacters(in: .whitespaces)) ?? 0
        settings.sshIdentityFile = sshIdentityFile.trimmingCharacters(in: .whitespaces)
        settings.remoteCommand = remoteCommand
        settings.remoteLoginShell = remoteLoginShell.trimmingCharacters(in: .whitespaces)
        settings.remoteWorkingDirectory = remoteWorkingDirectory.trimmingCharacters(in: .whitespaces)
        onChange()
        log += "\n[已保存]\n"
    }

    // MARK: - 执行

    private func run(command: String, label: String) {
        guard !busy else { return }
        busy = true
        log += "\n$ \(command)\n"
        ShellRunner.run(command, environment: ShellEnvironment.childEnvironment()) { [weak self] text in
            guard let self else { return }
            DispatchQueue.main.async { self.log += text }
        } onFinish: { [weak self] code in
            guard let self else { return }
            DispatchQueue.main.async {
                self.busy = false
                self.log += "\n[\(label) 退出码 \(code)]\n"
                self.refreshLocal()
            }
        }
    }

    private func openInTerminal(command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            NSLog("TokCat: 打开终端失败 \(error)")
        }
    }
}
