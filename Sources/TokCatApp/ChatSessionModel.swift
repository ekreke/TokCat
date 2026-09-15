import Foundation
import TokCatAgent
import TokCatCore
import UniformTypeIdentifiers

/// Chat 弹窗的视图模型：驱动一个**常驻**的 ACP 会话。
///
/// 生命周期：
/// - 左键打开 → `ensureSession`：已就绪且配置未变则复用，否则启动。
/// - 关闭弹窗**不结束**会话；空闲超过 `idleReapInterval` 才回收进程。
/// - 换 Agent / 改工作目录 / 退出 App → `shutdown()`。
///
/// 会话历史仅保留**内存**（当前会话）；重连/换 Agent 会清空。
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

    /// 一条对话记录（用户提问或 agent 回答）。
    struct ChatMessage: Identifiable, Equatable {
        enum Role: Equatable { case user, agent }

        let id: UUID
        let role: Role
        var text: String
        /// 图片附件缩略图数据。
        var images: [Data]
        /// 文件附件名（非图片）。
        var fileNames: [String]
        var isStreaming: Bool

        init(
            id: UUID = UUID(),
            role: Role,
            text: String = "",
            images: [Data] = [],
            fileNames: [String] = [],
            isStreaming: Bool = false
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.images = images
            self.fileNames = fileNames
            self.isStreaming = isStreaming
        }
    }

    @Published private(set) var status: Status = .idle
    /// 当前会话的对话记录（内存）。
    @Published private(set) var messages: [ChatMessage] = []
    /// 流式回答的节流展示文本（用于正在生成的那条消息）。
    @Published private(set) var streamingDisplayText: String = ""
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
    private var streamingMessageID: UUID?

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
        resetConversation()
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
    }

    /// 彻底断开：回收进程并清空会话状态。
    func shutdown() {
        teardownClient()
        activeConfiguration = nil
        resolvePermission(with: .cancelled)
        sessionId = nil
        status = .idle
        activity = ""
        resetConversation()
        stopIdleTimer()
    }

    private func teardownClient() {
        client?.stop()
        client = nil
    }

    private func resetConversation() {
        messages = []
        streamingMessageID = nil
        streamingDisplayText = ""
        attachments = []
        commands = []
        notice = ""
        throttle.reset()
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
                self.finishStreaming()
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

        // 记录用户提问（含附件缩略图/文件名）。
        let images = attachments.compactMap(\.previewData)
        let fileNames = attachments.filter { $0.previewData == nil }.map(\.name)
        messages.append(ChatMessage(role: .user, text: text, images: images, fileNames: fileNames))

        // 追加 agent 流式占位。
        let agentMessage = ChatMessage(role: .agent, isStreaming: true)
        messages.append(agentMessage)
        streamingMessageID = agentMessage.id
        streamingDisplayText = ""

        input = ""
        attachments = []
        notice = ""
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
                self.finishStreaming()
            } catch {
                self.status = .failed(error.localizedDescription)
                self.activity = ""
                self.finishStreaming()
            }
        }
    }

    func cancel() {
        guard let client, let sessionId else { return }
        client.cancel(sessionId: sessionId)
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

    // MARK: - @ 引用文件

    private var fileIndex: [String] = []
    private var fileIndexRoot: String?

    /// 会话工作目录下的文件相对路径（用于 `@` 引用），带缓存。
    func fileSuggestions(query: String) -> [String] {
        guard let root = activeConfiguration?.sessionCWD, !root.isEmpty else { return [] }
        if fileIndexRoot != root {
            fileIndexRoot = root
            fileIndex = Self.enumerateFiles(root: root)
        }
        let lowered = query.lowercased()
        let matches = lowered.isEmpty ? fileIndex : fileIndex.filter { $0.lowercased().contains(lowered) }
        return Array(matches.prefix(8))
    }

    private static func enumerateFiles(root: String, limit: Int = 3000) -> [String] {
        let rootURL = URL(fileURLWithPath: root)
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        let skipDirectories: Set<String> = [
            ".git", "node_modules", ".build", "DerivedData", "dist", "build",
            ".venv", "venv", "__pycache__", ".next", "target",
        ]
        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        var result: [String] = []
        for case let url as URL in enumerator {
            if url.hasDirectoryPath {
                if skipDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            var relative = url.path
            if relative.hasPrefix(prefix) {
                relative = String(relative.dropFirst(prefix.count))
            }
            result.append(relative)
            if result.count >= limit { break }
        }
        return result
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
            appendAgentText(text)
            if pendingPermission == nil { activity = "" }
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
        finishStreaming()
    }

    // MARK: - 流式渲染

    private func appendAgentText(_ chunk: String) {
        guard let id = streamingMessageID,
              let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += chunk
        scheduleDisplayFlush()
    }

    /// 结束当前流式消息（跟随其显示文本）。
    private func finishStreaming() {
        if let id = streamingMessageID, let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].isStreaming = false
        }
        streamingMessageID = nil
        streamingDisplayText = ""
    }

    /// 回答增量到达时调用：按 150ms 节流刷新 Markdown 快照。
    private func scheduleDisplayFlush() {
        throttle.submit { [weak self] in
            guard let self,
                  let id = self.streamingMessageID,
                  let message = self.messages.first(where: { $0.id == id }) else { return }
            self.streamingDisplayText = message.text
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }
}
