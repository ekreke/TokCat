import Foundation

/// ACP 客户端错误。
public enum ACPClientError: Error, LocalizedError {
    case notRunning
    case processLaunchFailed(String)
    case terminated(exitCode: Int32, stderr: String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            return "agent 进程未运行"
        case let .processLaunchFailed(reason):
            return "无法启动 agent：\(reason)"
        case let .terminated(code, stderr):
            let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return tail.isEmpty ? "agent 进程已退出（code \(code)）" : "agent 进程已退出（code \(code)）：\(tail)"
        case let .invalidResponse(message):
            return "agent 返回异常：\(message)"
        }
    }
}

/// 启动配置：可执行文件绝对路径 + 参数 + 工作目录 + 环境变量。
public struct ACPLaunchConfiguration: Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]
    /// 进程启动目录（本地）。
    public var cwd: String
    /// 传给 `session/new` 的工作目录（远程模式下是远端路径）。默认等于 `cwd`。
    public var sessionCWD: String
    public var environment: [String: String]?

    public init(
        executablePath: String,
        arguments: [String],
        cwd: String,
        sessionCWD: String? = nil,
        environment: [String: String]? = nil
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.cwd = cwd
        if let sessionCWD, !sessionCWD.isEmpty {
            self.sessionCWD = sessionCWD
        } else {
            self.sessionCWD = cwd
        }
        self.environment = environment
    }
}

/// ACP 会话客户端：以子进程方式启动 agent，按行收发 JSON-RPC。
///
/// - 流式更新通过 `onEvent` 回调（主线程）抛出。
/// - 反向的 `session/request_permission` 通过 `permissionHandler` 处理；
///   未设置时默认拒绝。
/// - 我们不在 `initialize` 中声明 fs / terminal 能力，因此这些反向请求
///   一律回 method-not-found，agent 会退回自带工具。
public final class ACPClient: @unchecked Sendable {
    public typealias PermissionHandler = @Sendable (ACPPermissionParams) async -> ACPPermissionResult

    /// 流式事件回调（主线程）。
    public var onEvent: (@Sendable (AgentEvent) -> Void)?
    /// 进程退出回调（主线程）。
    public var onExit: (@Sendable (Int32) -> Void)?
    /// 权限请求处理。
    public var permissionHandler: PermissionHandler?

    public private(set) var stderrTail = ""

    private let configuration: ACPLaunchConfiguration
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let queue = DispatchQueue(label: "tokcat.acp.io")
    private let lock = NSLock()

    private var readBuffer = Data()
    private var nextRequestID = 1
    private var pending: [JSONRPCID: CheckedContinuation<JSONValue, Error>] = [:]
    private var running = false

    public init(configuration: ACPLaunchConfiguration) {
        self.configuration = configuration
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    // MARK: - 生命周期

    public func launch() throws {
        process.executableURL = URL(fileURLWithPath: configuration.executablePath)
        process.arguments = configuration.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: configuration.cwd)
        if let environment = configuration.environment {
            process.environment = environment
        }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.enqueue(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.appendStderr(String(decoding: data, as: UTF8.self))
        }
        process.terminationHandler = { [weak self] proc in
            self?.handleTermination(exitCode: proc.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            throw ACPClientError.processLaunchFailed(error.localizedDescription)
        }
        lock.lock(); running = true; lock.unlock()
    }

    public func stop() {
        lock.lock()
        let wasRunning = running
        running = false
        let continuations = Array(pending.values)
        pending.removeAll()
        lock.unlock()

        continuations.forEach { $0.resume(throwing: ACPClientError.notRunning) }
        guard wasRunning || process.isRunning else { return }
        process.terminationHandler = nil
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        process.terminate()
    }

    // MARK: - 请求

    @discardableResult
    public func initialize(clientInfo: ACPImplementation) async throws -> ACPInitializeResult {
        let params = ACPInitializeParams(clientInfo: clientInfo)
        let result = try await request(method: ACPMethod.initialize, params: try params.jsonValue())
        return try result.decode(ACPInitializeResult.self)
    }

    public func authenticate(methodId: String) async throws {
        let params: JSONValue = .object(["methodId": .string(methodId)])
        _ = try await request(method: ACPMethod.authenticate, params: params)
    }

    public func newSession(cwd: String) async throws -> ACPNewSessionResult {
        let params = ACPNewSessionParams(cwd: cwd)
        let result = try await request(method: ACPMethod.sessionNew, params: try params.jsonValue())
        return try result.decode(ACPNewSessionResult.self)
    }

    public func prompt(sessionId: String, text: String) async throws -> ACPPromptResult {
        try await prompt(sessionId: sessionId, content: [.text(text)])
    }

    /// 发送一组内容块（文本 / 图片 / resource 等）。
    public func prompt(sessionId: String, content: [ACPContentBlock]) async throws -> ACPPromptResult {
        let params = ACPPromptParams(sessionId: sessionId, prompt: content)
        let result = try await request(method: ACPMethod.sessionPrompt, params: try params.jsonValue())
        return try result.decode(ACPPromptResult.self)
    }

    public func setMode(sessionId: String, modeId: String) async throws {
        let params = ACPSetModeParams(sessionId: sessionId, modeId: modeId)
        _ = try await request(method: ACPMethod.sessionSetMode, params: try params.jsonValue())
    }

    /// `session/cancel` 是通知，不等响应。
    public func cancel(sessionId: String) {
        let params = ACPSessionIDParams(sessionId: sessionId)
        guard let value = try? params.jsonValue() else { return }
        let notification = JSONRPCNotification(method: ACPMethod.sessionCancel, params: value)
        try? send(notification)
    }

    // MARK: - 内部

    private func request(method: String, params: JSONValue) async throws -> JSONValue {
        let id = allocateID()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard running else {
                lock.unlock()
                continuation.resume(throwing: ACPClientError.notRunning)
                return
            }
            pending[id] = continuation
            lock.unlock()

            do {
                try send(JSONRPCRequest(id: id, method: method, params: params))
            } catch {
                resume(id: id, with: .failure(error))
            }
        }
    }

    private func allocateID() -> JSONRPCID {
        lock.lock(); defer { lock.unlock() }
        let id = nextRequestID
        nextRequestID += 1
        return .number(id)
    }

    private func send(_ request: JSONRPCRequest) throws {
        let data = try JSONRPCCodec.encode(request)
        writeLine(data)
    }

    private func send(_ notification: JSONRPCNotification) throws {
        let object: [String: JSONValue] = [
            "jsonrpc": "2.0",
            "method": .string(notification.method),
            "params": notification.params,
        ]
        let data = try JSONEncoder().encode(JSONValue.object(object))
        writeLine(data)
    }

    private func send(_ response: JSONRPCResponse) throws {
        let data = try JSONRPCCodec.encode(response)
        writeLine(data)
    }

    private func send(_ response: JSONRPCErrorResponse) throws {
        let data = try JSONRPCCodec.encode(response)
        writeLine(data)
    }

    private func writeLine(_ data: Data) {
        var line = data
        line.append(0x0A)
        stdinPipe.fileHandleForWriting.write(line)
    }

    private func enqueue(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            self.readBuffer.append(data)
            while let newline = self.readBuffer.firstIndex(of: 0x0A) {
                let line = self.readBuffer[self.readBuffer.startIndex..<newline]
                self.readBuffer.removeSubrange(self.readBuffer.startIndex...newline)
                guard !line.isEmpty else { continue }
                self.handle(line: Data(line))
            }
        }
    }

    private func handle(line: Data) {
        guard let message = try? JSONRPCCodec.decode(line: line) else { return }
        switch message {
        case let .response(response):
            resume(id: response.id, with: .success(response.result))
        case let .error(response):
            if let id = response.id {
                resume(id: id, with: .failure(response.error))
            }
        case let .notification(notification):
            handle(notification: notification)
        case let .request(request):
            handle(request: request)
        }
    }

    private func handle(notification: JSONRPCNotification) {
        guard notification.method == ACPMethod.sessionUpdate else { return }
        let params = ACPSessionUpdateParams(json: notification.params)
        guard let event = params.update.agentEvent else { return }
        emit(event)
    }

    private func handle(request: JSONRPCRequest) {
        switch request.method {
        case ACPMethod.requestPermission:
            let params = (try? request.params.decode(ACPPermissionParams.self))
                ?? ACPPermissionParams(sessionId: "", toolCall: nil, options: [])
            Task { [weak self] in
                guard let self else { return }
                let result: ACPPermissionResult
                if let handler = self.permissionHandler {
                    result = await handler(params)
                } else {
                    result = .cancelled
                }
                let value = (try? result.jsonValue()) ?? .null
                try? self.send(JSONRPCResponse(id: request.id, result: value))
            }
        default:
            // 未声明的能力（fs / terminal 等）一律回 method-not-found。
            try? send(JSONRPCErrorResponse(
                id: request.id,
                error: JSONRPCError(code: JSONRPCError.methodNotFound, message: "unsupported method: \(request.method)")
            ))
        }
    }

    private func resume(id: JSONRPCID, with result: Result<JSONValue, Error>) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func handleTermination(exitCode: Int32) {
        lock.lock()
        running = false
        let continuations = Array(pending.values)
        pending.removeAll()
        let stderr = stderrTail
        lock.unlock()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        continuations.forEach {
            $0.resume(throwing: ACPClientError.terminated(exitCode: exitCode, stderr: stderr))
        }
        DispatchQueue.main.async { [weak self] in
            self?.onExit?(exitCode)
        }
    }

    private func appendStderr(_ text: String) {
        lock.lock()
        stderrTail += text
        if stderrTail.count > 4000 {
            stderrTail = String(stderrTail.suffix(4000))
        }
        lock.unlock()
    }

    private func emit(_ event: AgentEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}
