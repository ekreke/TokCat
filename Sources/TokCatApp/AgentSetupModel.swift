import AppKit
import Foundation
import TokCatAgent

/// 「Agent 检测 / 一键安装」窗口的视图模型。
final class AgentSetupModel: ObservableObject {
    struct Row: Identifiable {
        let preset: AgentPreset
        let installed: Bool
        let path: String?
        var id: String { preset.id }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var log: String = ""
    @Published private(set) var busy: Bool = false
    @Published var customCommand: String

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        self.customCommand = settings.customAgentCommand
        refresh()
    }

    func refresh() {
        ShellEnvironment.invalidateCache()
        rows = AgentPreset.builtins.map { preset in
            switch AgentDetector.status(for: preset, customCommand: customCommand) {
            case let .ready(path):
                return Row(preset: preset, installed: true, path: path)
            case .missing:
                return Row(preset: preset, installed: false, path: nil)
            }
        }
    }

    func install(_ preset: AgentPreset) {
        guard let command = preset.installCommand else { return }
        run(command: command, label: "安装 \(preset.displayName)")
    }

    func openLogin(_ preset: AgentPreset) {
        guard let command = preset.loginCommand else { return }
        openInTerminal(command: command)
    }

    func openDocs(_ preset: AgentPreset) {
        guard let raw = preset.docsURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    func saveCustomCommand() {
        settings.customAgentCommand = customCommand
        settings.agentPresetId = AgentPreset.customID
        refresh()
    }

    private func run(command: String, label: String) {
        guard !busy else { return }
        busy = true
        log += "\n$ \(command)\n"
        ShellRunner.run(command, environment: ShellEnvironment.childEnvironment()) { [weak self] text in
            DispatchQueue.main.async { self?.log += text }
        } onFinish: { [weak self] code in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.log += "\n[\(label) 退出码 \(code)]\n"
                self.refresh()
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
