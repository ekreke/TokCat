import Foundation
import TokCatAgent

/// Chat 弹窗的视图模型：驱动一次 ACP 会话（可多轮追问，只显示最新回答）。
///
/// 所有公开发起的方法都应在主线程调用；来自 agent 的回调统一跳回主线程。
final class ChatSessionModel: ObservableObject, @unchecked Sendable {
    enum Status: Equatable {
        case idle
        case starting
        case ready
        case running
        case failed(String)

        var isBusy: Bool { self == .starting || self == .running }
    }

    struct PendingPermission: Identifiable {
        let id = UUID()
        let title: String
        let options: [ACPPermissionOption]
    }

    @Published private(set) var status: Status = .idle
    /// 最新一条回答（流式累积；每次发送前清空）。
    @Published private(set) var answer: String = ""
    /// 当前活动提示（思考中 / 运行工具 / 等待授权）。
    @Published private(set) var activity: String = ""
    @Published var input: String = ""
    @Published private(set) var agentName: String = ""
    @Published private(set) var pendingPermission: PendingPermission?

    private var client: ACPClient?
    private var sessionId: String?
    private var permissionContinuation: CheckedContinuation<ACPPermissionResult, Never>?

    var canSend: Bool {
        status == .ready && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 生命周期

    /// 启动会话：launch 进程 → initialize → session/new。
    func start(configuration: ACPLaunchConfiguration, displayName: String) {
        stop()
        agentName = displayName
        answer = ""
        activity = "连接中…"
        status = .starting

        let client = ACPClient(configuration: configuration)
        client.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        client.onExit = { [weak self] code in
            Task { @MainActor in self?.handleExit(code) }
        }
        client.permissionHandler = { [weak self] params in
            guard let self else { return .cancelled }
            return await self.requestPermission(params)
        }
        self.client = client

        Task { @MainActor in
            do {
                try client.launch()
                let initialized = try await client.initialize(
                    clientInfo: ACPImplementation(name: "TokCat", title: "TokCat", version: AppInfo.version)
                )
                if initialized.protocolVersion != ACPProtocolVersion {
                    // 版本不一致不致命，仅记录；继续尝试。
                    NSLog("TokCat: ACP 协议版本不一致 agent=\(initialized.protocolVersion ?? -1)")
                }
                guard let session = try? await client.newSession(cwd: configuration.cwd) else {
                    throw ACPClientError.invalidResponse("session/new 无 sessionId")
                }
                self.sessionId = session.sessionId
                self.status = .ready
                self.activity = ""
            } catch {
                self.status = .failed(error.localizedDescription)
                self.activity = ""
            }
        }
    }

    /// 直接进入失败态（例如 agent 未安装），供控制器展示安装引导。
    func reportUnavailable(displayName: String, message: String) {
        stop()
        agentName = displayName
        status = .failed(message)
        activity = ""
        answer = ""
    }

    func stop() {
        permissionContinuation?.resume(returning: .cancelled)
        permissionContinuation = nil
        pendingPermission = nil
        client?.stop()
        client = nil
        sessionId = nil
        if status != .idle {
            status = .idle
        }
        activity = ""
        answer = ""
    }

    // MARK: - 对话

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client, let sessionId, status == .ready else { return }
        input = ""
        answer = ""
        activity = "思考中…"
        status = .running

        Task { @MainActor in
            do {
                _ = try await client.prompt(sessionId: sessionId, text: text)
                if self.status == .running {
                    self.status = .ready
                    self.activity = ""
                }
            } catch {
                self.status = .failed(error.localizedDescription)
                self.activity = ""
            }
        }
    }

    func cancel() {
        guard let client, let sessionId else { return }
        client.cancel(sessionId: sessionId)
    }

    // MARK: - 权限

    func choosePermission(optionId: String) {
        finishPermission(with: .selected(optionId))
    }

    func denyPermission() {
        finishPermission(with: .cancelled)
    }

    private func requestPermission(_ params: ACPPermissionParams) async -> ACPPermissionResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.permissionContinuation = continuation
                self.pendingPermission = PendingPermission(
                    title: params.toolCall?.title ?? "需要授权",
                    options: params.options
                )
                self.activity = "等待授权…"
            }
        }
    }

    private func finishPermission(with result: ACPPermissionResult) {
        pendingPermission = nil
        activity = status == .running ? "思考中…" : ""
        permissionContinuation?.resume(returning: result)
        permissionContinuation = nil
    }

    // MARK: - 事件

    private func handle(_ event: AgentEvent) {
        switch event {
        case let .agentText(text):
            answer += text
            if pendingPermission == nil { activity = "" }
        case .agentThought:
            if status == .running, pendingPermission == nil { activity = "思考中…" }
        case let .toolCall(title):
            if pendingPermission == nil { activity = "运行工具：\(title)" }
        case let .toolUpdate(_, statusText):
            if pendingPermission == nil, let statusText { activity = "工具：\(statusText)" }
        case .plan:
            break
        }
    }

    private func handleExit(_ code: Int32) {
        guard status != .idle else { return }
        status = .failed("agent 已退出（code \(code)）")
        activity = ""
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }
}
