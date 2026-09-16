import Foundation
import TokCatAgent

/// 在 CLI 内驱动一个 ACP 会话，把协议事件转成 JSON 事件流（供 Windows 外壳消费）。
///
/// 复用 `ACPClient` / `AgentDetector`；权限请求挂起直到收到 `agent.permission.reply`。
final class AgentBridge {
    private var client: ACPClient?
    private var sessionId: String?
    private var agentName = "Hermes"
    private var permissionContinuation: CheckedContinuation<ACPPermissionResult, Never>?
    private let lock = NSLock()

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return client?.isRunning ?? false
    }

    // MARK: - 连接

    func connect(params: [String: Any]) {
        disconnect()
        let mode = params["mode"] as? String ?? "local"
        let cwd = params["cwd"] as? String ?? FileManager.default.homeDirectoryForCurrentUser.path

        var configuration: ACPLaunchConfiguration?
        var displayName = "Hermes"

        if mode == "remote", let remote = params["remote"] as? [String: Any] {
            let target = (remote["target"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let config = RemoteSSHConfig(
                target: target,
                port: (remote["port"] as? NSNumber)?.intValue,
                identityFile: remote["identityFile"] as? String,
                remoteCommand: (remote["remoteCommand"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "hermes acp",
                loginShell: remote["loginShell"] as? String ?? "",
                remoteWorkingDirectory: remote["remoteWorkingDirectory"] as? String ?? ""
            )
            configuration = AgentDetector.remoteLaunchConfiguration(config, localCWD: cwd)
            displayName = target.isEmpty ? "Hermes · 远程" : "Hermes · \(target)"
        } else {
            configuration = AgentDetector.localLaunchConfiguration(cwd: cwd)
        }

        guard let configuration else {
            emit(["event": "agent.failed", "message": "未检测到 Hermes 可执行文件，或远程 SSH 配置不完整。"])
            return
        }

        let client = ACPClient(configuration: configuration)
        client.onEvent = { [weak self] event in self?.emitEvent(event) }
        client.onExit = { code in
            emit(["event": "agent.exit", "code": Int(code)])
        }
        client.permissionHandler = { [weak self] params in
            guard let self else { return .cancelled }
            return await self.requestPermission(params)
        }

        lock.lock()
        self.client = client
        self.sessionId = nil
        self.agentName = displayName
        lock.unlock()

        let name = displayName
        Task { @MainActor in
            do {
                try client.launch()
                let initialized = try await client.initialize(
                    clientInfo: ACPImplementation(name: "TokCat", title: "TokCat", version: TokCatVersion.string)
                )
                let caps = initialized.agentCapabilities?.promptCapabilities
                let session = try await client.newSession(cwd: configuration.sessionCWD)
                self.lock.lock()
                self.sessionId = session.sessionId
                self.lock.unlock()
                emit([
                    "event": "agent.ready",
                    "sessionId": session.sessionId,
                    "agentName": name,
                    "capabilities": [
                        "image": caps?.image ?? false,
                        "embeddedContext": caps?.embeddedContext ?? false,
                    ],
                ])
            } catch {
                emit(["event": "agent.failed", "message": error.localizedDescription])
            }
        }
    }

    // MARK: - 对话

    func prompt(params: [String: Any]) {
        lock.lock()
        let client = self.client
        let sessionId = self.sessionId
        lock.unlock()

        guard let client, let sessionId else {
            emit(["event": "agent.error", "message": "agent 未连接"])
            return
        }
        let content = AgentBridge.content(from: params)
        guard !content.isEmpty else { return }

        Task { @MainActor in
            do {
                let result = try await client.prompt(sessionId: sessionId, content: content)
                emit(["event": "agent.turnEnd", "stopReason": result.stopReason ?? ""])
            } catch {
                emit(["event": "agent.error", "message": error.localizedDescription])
            }
        }
    }

    func cancel() {
        lock.lock()
        let client = self.client
        let sessionId = self.sessionId
        lock.unlock()
        guard let client, let sessionId else { return }
        client.cancel(sessionId: sessionId)
    }

    func replyPermission(params: [String: Any]) {
        let result: ACPPermissionResult
        if let optionId = params["optionId"] as? String, !optionId.isEmpty {
            result = .selected(optionId)
        } else {
            result = .cancelled
        }
        lock.lock()
        let continuation = permissionContinuation
        permissionContinuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }

    func disconnect() {
        lock.lock()
        let continuation = permissionContinuation
        permissionContinuation = nil
        let client = self.client
        self.client = nil
        self.sessionId = nil
        lock.unlock()
        continuation?.resume(returning: .cancelled)
        client?.stop()
    }

    // MARK: - 内部

    private func requestPermission(_ params: ACPPermissionParams) async -> ACPPermissionResult {
        await withCheckedContinuation { continuation in
            lock.lock()
            permissionContinuation = continuation
            lock.unlock()
            emit([
                "event": "agent.permission",
                "title": params.toolCall?.title ?? "需要授权",
                "options": params.options.map {
                    ["optionId": $0.optionId, "name": $0.name ?? $0.optionId, "kind": $0.kind ?? ""]
                },
            ])
        }
    }

    private func emitEvent(_ event: AgentEvent) {
        switch event {
        case let .agentText(text):
            emit(["event": "agent.event", "kind": "text", "text": text])
        case let .agentThought(text):
            emit(["event": "agent.event", "kind": "thought", "text": text])
        case let .toolCall(title):
            emit(["event": "agent.event", "kind": "tool", "title": title])
        case let .toolUpdate(title, status):
            emit(["event": "agent.event", "kind": "toolUpdate", "title": title ?? "", "status": status ?? ""])
        case let .plan(entries):
            emit(["event": "agent.event", "kind": "plan", "entries": entries])
        case let .availableCommands(commands):
            emit([
                "event": "agent.event",
                "kind": "commands",
                "commands": commands.map { ["name": $0.name, "description": $0.description, "hint": $0.inputHint ?? ""] },
            ])
        }
    }

    /// 从 params 组装内容块：优先 `content`，否则 `text`。
    static func content(from params: [String: Any]) -> [ACPContentBlock] {
        if let raw = params["content"] as? [[String: Any]] {
            return raw.compactMap { block in
                switch block["type"] as? String {
                case "text":
                    let text = block["text"] as? String ?? ""
                    return text.isEmpty ? nil : .text(text)
                case "image":
                    guard let mime = block["mimeType"] as? String, let data = block["data"] as? String else { return nil }
                    return .image(mimeType: mime, data: data)
                case "resource_link":
                    return .resourceLink(
                        uri: block["uri"] as? String ?? "",
                        name: block["name"] as? String ?? "",
                        mimeType: block["mimeType"] as? String,
                        size: (block["size"] as? NSNumber)?.intValue
                    )
                case "resource":
                    guard let resource = block["resource"] as? [String: Any] else { return nil }
                    return .embeddedResource(
                        uri: resource["uri"] as? String ?? "",
                        mimeType: resource["mimeType"] as? String,
                        text: resource["text"] as? String ?? ""
                    )
                default:
                    return nil
                }
            }
        }
        if let text = params["text"] as? String, !text.isEmpty {
            return [.text(text)]
        }
        return []
    }
}
