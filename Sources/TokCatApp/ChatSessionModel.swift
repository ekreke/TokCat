import Foundation
import TokCatAgent
import TokCatCore
import UniformTypeIdentifiers

/// Chat 弹窗的视图模型：驱动一个**常驻**的 ACP 会话（可多轮追问，只显示最新回答）。
///
/// 生命周期：
/// - 左键打开 → `ensureSession`：已就绪且配置未变则复用，否则启动。
/// - 关闭弹窗**不结束**会话；空闲超过 `idleReapInterval` 才回收进程。
/// - 换 Agent / 改工作目录 / 退出 App → `shutdown()`。
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

    /// 待发送的附件（图片 / 文件 / 内嵌 resource）。
    struct PendingAttachment: Identifiable, Equatable {
        let id: UUID
        let name: String
        /// 供缩略图使用的图片数据（仅图片附件非空）。
        let previewData: Data?
        /// 组装好的 ACP 内容块（发送时直接使用）。
        let block: ACPContentBlock

        init(id: UUID = UUID(), name: String, previewData: Data? = nil, block: ACPContentBlock) {
            self.id = id
            self.name = name
            self.previewData = previewData
            self.block = block
        }
    }

    @Published private(set) var status: Status = .idle
    /// 最新一条回答（流式累积；每次发送前清空）。
    @Published private(set) var answer: String = ""
    /// 供 Markdown 渲染的节流快照（避免每个 token 都重解析整段）。
    @Published private(set) var displayAnswer: String = ""
    /// 当前活动提示（思考中 / 运行工具 / 等待授权）。
    @Published private(set) var activity: String = ""
    @Published var input: String = ""
    @Published private(set) var agentName: String = ""
    @Published private(set) var pendingPermission: PendingPermission?
    /// 待发送附件。
    @Published private(set) var attachments: [PendingAttachment] = []
    /// agent 广播的可用斜杠命令。
    @Published private(set) var commands: [ACPCommand] = []
    /// agent 是否声明图片输入能力。
    @Published private(set) var imageSupported = false
    /// agent 是否声明内嵌资源（embeddedContext）能力。
    @Published private(set) var embeddedContextSupported = false
    /// 一次性提示（如能力不支持、附件过大）。
    @Published var notice: String = ""

    private var client: ACPClient?
    private var sessionId: String?
    private var activeConfiguration: ACPLaunchConfiguration?
    private var permissionContinuation: CheckedContinuation<ACPPermissionResult, Never>?

    private var idleTimer: Timer?
    private var lastActivity = Date()
    /// 空闲回收阈值。
    private let idleReapInterval: TimeInterval = 3600
    private let idleCheckInterval: TimeInterval = 60
    /// 流式 Markdown 渲染节流（150ms）。
    private let throttle = StreamingTextThrottle(interval: 0.15)

    var canSend: Bool {
        status == .ready
            && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    // MARK: - 生命周期

    /// 确保有一个可用的会话：已就绪且配置未变则复用，否则（首次 / 失败 / 配置变）启动。
    func ensureSession(configuration: ACPLaunchConfiguration, displayName: String) {
        if activeConfiguration == configuration,
           let client, client.isRunning,
           sessionId != nil,
           status == .ready || status == .running || status == .starting {
            touch()
            return
        }
        start(configuration: configuration, displayName: displayName)
    }

    private func start(configuration: ACPLaunchConfiguration, displayName: String) {
        teardownClient()
        resolvePermission(with: .cancelled)
        sessionId = nil
        activeConfiguration = configuration
        agentName = displayName
        answer = ""
        displayAnswer = ""
        attachments = []
        commands = []
        notice = ""
        throttle.reset()
        activity = "连接中…"
        status = .starting
        touch()

        let client = ACPClient(configuration: configuration)
        client.onEvent = { [weak self] event in
            guard let self else { return }
            Task { @MainActor in self.handle(event) }
        }
        client.onExit = { [weak self] code in
            guard let self else { return }
            Task { @MainActor in self.handleExit(code) }
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
                let promptCapabilities = initialized.agentCapabilities?.promptCapabilities
                self.imageSupported = promptCapabilities?.image ?? false
                self.embeddedContextSupported = promptCapabilities?.embeddedContext ?? false
                guard let session = try? await client.newSession(cwd: configuration.sessionCWD) else {
                    throw ACPClientError.invalidResponse("session/new 无 sessionId")
                }
                // 期间可能已被替换/关闭，避免覆盖新状态。
                guard self.client === client else { return }
                self.sessionId = session.sessionId
                self.status = .ready
                self.activity = ""
            } catch {
                guard self.client === client else { return }
                self.status = .failed(error.localizedDescription)
                self.activity = ""
            }
        }
    }

    /// 直接进入失败态（例如 agent 未安装），供控制器展示安装引导。
    func reportUnavailable(displayName: String, message: String) {
        shutdown()
        agentName = displayName
        status = .failed(message)
        activity = ""
        answer = ""
        displayAnswer = ""
    }

    /// 彻底断开：回收进程并清空会话状态。
    func shutdown() {
        teardownClient()
        activeConfiguration = nil
        resolvePermission(with: .cancelled)
        sessionId = nil
        status = .idle
        activity = ""
        answer = ""
        displayAnswer = ""
        throttle.reset()
        stopIdleTimer()
    }

    private func teardownClient() {
        client?.stop()
        client = nil
    }

    // MARK: - 空闲回收

    private func touch() {
        lastActivity = Date()
        startIdleTimerIfNeeded()
    }

    private func startIdleTimerIfNeeded() {
        guard idleTimer == nil else { return }
        let timer = Timer(timeInterval: idleCheckInterval, repeats: true) { [weak self] _ in
            guard let self, let client = self.client, client.isRunning else { return }
            if Date().timeIntervalSince(self.lastActivity) >= self.idleReapInterval {
                NSLog("TokCat: ACP 会话空闲 \(Int(self.idleReapInterval / 60)) 分钟，回收进程")
                self.teardownClient()
                self.activeConfiguration = nil
                self.sessionId = nil
                self.status = .idle
                self.activity = "已空闲断开"
                self.stopIdleTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    // MARK: - 对话

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == .ready, let client, let sessionId,
              !text.isEmpty || !attachments.isEmpty else { return }

        var blocks: [ACPContentBlock] = []
        if !text.isEmpty { blocks.append(.text(text)) }
        blocks.append(contentsOf: attachments.map(\.block))
        let content = blocks

        input = ""
        attachments = []
        notice = ""
        answer = ""
        displayAnswer = ""
        throttle.reset()
        activity = "思考中…"
        status = .running
        touch()

        Task { @MainActor in
            do {
                _ = try await client.prompt(sessionId: sessionId, content: content)
                if self.status == .running {
                    self.status = .ready
                    self.activity = ""
                }
                self.forceDisplayFlush()
            } catch {
                self.status = .failed(error.localizedDescription)
                self.activity = ""
                self.forceDisplayFlush()
            }
        }
    }

    // MARK: - 附件

    /// 添加图片附件（传入已编码的图片数据）。
    func addImageAttachment(data: Data, mimeType: String, name: String) {
        guard imageSupported else {
            notice = "当前 agent 未声明图片输入能力，无法发送图片。"
            return
        }
        let block = ACPContentBlock.image(mimeType: mimeType, data: data.base64EncodedString())
        attachments.append(PendingAttachment(name: name, previewData: data, block: block))
    }

    /// 添加文件附件：文本类且支持 embeddedContext 时内嵌，否则用 resource_link。
    func addFileAttachment(url: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue
        let mime = Self.mimeType(for: url)
        let name = url.lastPathComponent

        if embeddedContextSupported, let size, size <= Self.maxEmbeddedBytes,
           let text = Self.readTextIfSmall(url) {
            let block = ACPContentBlock.embeddedResource(uri: url.absoluteString, mimeType: mime, text: text)
            attachments.append(PendingAttachment(name: name, block: block))
            return
        }
        let block = ACPContentBlock.resourceLink(uri: url.absoluteString, name: name, mimeType: mime, size: size)
        attachments.append(PendingAttachment(name: name, block: block))
    }

    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    func clearAttachments() {
        attachments = []
    }

    private static let maxEmbeddedBytes = 1_000_000

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "jsonc", "yaml", "yml", "toml", "ini", "cfg",
        "swift", "c", "h", "cpp", "hpp", "m", "mm", "cs", "java", "kt", "go", "rs",
        "py", "rb", "php", "js", "jsx", "ts", "tsx", "css", "scss", "html", "xml",
        "sh", "bash", "zsh", "fish", "ps1", "sql", "log", "csv", "tsv", "env", "gitignore",
    ]

    private static func readTextIfSmall(_ url: URL) -> String? {
        guard textExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func mimeType(for url: URL) -> String? {
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.preferredMIMEType
        }
        return nil
    }

    func cancel() {
        guard let client, let sessionId else { return }
        client.cancel(sessionId: sessionId)
    }

    // MARK: - 权限

    func choosePermission(optionId: String) {
        resolvePermission(with: .selected(optionId))
    }

    func denyPermission() {
        resolvePermission(with: .cancelled)
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
                self.touch()
            }
        }
    }

    private func resolvePermission(with result: ACPPermissionResult) {
        guard let continuation = permissionContinuation else { return }
        pendingPermission = nil
        activity = status == .running ? "思考中…" : ""
        permissionContinuation = nil
        continuation.resume(returning: result)
    }

    // MARK: - 事件

    private func handle(_ event: AgentEvent) {
        touch()
        switch event {
        case let .agentText(text):
            answer += text
            if pendingPermission == nil { activity = "" }
            scheduleDisplayFlush()
        case .agentThought:
            if status == .running, pendingPermission == nil { activity = "思考中…" }
        case let .toolCall(title):
            if pendingPermission == nil { activity = "运行工具：\(title)" }
        case let .toolUpdate(_, statusText):
            if pendingPermission == nil, let statusText { activity = "工具：\(statusText)" }
        case .plan:
            break
        case let .availableCommands(commands):
            self.commands = commands
        }
    }

    private func handleExit(_ code: Int32) {
        guard status != .idle else { return }
        teardownClient()
        activeConfiguration = nil
        sessionId = nil
        status = .failed("agent 已退出（code \(code)）")
        activity = ""
        forceDisplayFlush()
    }

    // MARK: - 渲染节流

    /// 回答增量到达时调用：按 150ms 节流刷新 Markdown 快照。
    private func scheduleDisplayFlush() {
        throttle.submit { [weak self] in
            guard let self else { return }
            self.displayAnswer = self.answer
        }
    }

    /// 回答结束/失败时立即刷新，保证渲染完整内容。
    private func forceDisplayFlush() {
        throttle.force { [weak self] in
            guard let self else { return }
            self.displayAnswer = self.answer
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }
}
