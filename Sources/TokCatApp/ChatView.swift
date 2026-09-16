import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TokCatAgent

/// Chat 弹窗：对话记录（用户提问 + agent 回答）+ 富输入。
struct ChatView: View {
    @ObservedObject var model: ChatSessionModel
    /// 未安装 agent 时点击“安装 / 设置”。
    var onSetup: (() -> Void)?
    /// 右下角拖拽手柄的尺寸增量回调（由控制器换算成弹窗尺寸）。
    var onResize: ((CGSize) -> Void)?
    @State private var composerFocused = true
    @State private var lastDrag: CGSize = .zero
    /// 是否自动跟随到底部（用户向上滚动后关闭）。
    @State private var autoFollow = true
    private let bottomAnchor = "tokcat.chat.bottom"

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider()
                transcript
                if let permission = model.pendingPermission {
                    permissionBar(permission)
                }
                if !model.notice.isEmpty {
                    noticeBar
                }
                if !model.attachments.isEmpty {
                    attachmentBar
                }
                if !commandSuggestions.isEmpty {
                    commandBar
                }
                if !fileSuggestions.isEmpty {
                    fileBar
                }
                inputBar(maxComposerHeight: max(64, geometry.size.height * 0.2))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) { resizeHandle }
        }
        .onAppear { composerFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(model.agentName.isEmpty ? "Agent" : model.agentName)
                .font(.headline)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let onSetup {
                Button("设置", action: onSetup)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    // MARK: - 对话记录

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.messages.isEmpty {
                        emptyState
                    }
                    ForEach(model.messages) { message in
                        messageBubble(message).id(message.id)
                    }
                    if !model.activity.isEmpty, model.status == .running {
                        Text(model.activity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                        .onAppear { autoFollow = true }
                        .onDisappear { autoFollow = false }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .onChange(of: model.messages.count) { _ in
                autoFollow = true
                scrollToBottom(proxy)
            }
            .onChange(of: model.streamingDisplayText) { _ in
                if autoFollow { scrollToBottom(proxy) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !autoFollow {
                    Button {
                        autoFollow = true
                        scrollToBottom(proxy)
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("回到底部")
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        Group {
            if case let .failed(message) = model.status {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(model.activity.isEmpty ? "问点什么吧。" : model.activity)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func messageBubble(_ message: ChatSessionModel.ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if message.role == .user { Spacer(minLength: 20) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if !message.images.isEmpty || !message.fileNames.isEmpty {
                    attachmentsPreview(message)
                }
                let text = bubbleText(message)
                if !text.isEmpty {
                    bubbleBody(message, text: text)
                }
            }
            if message.role == .agent { Spacer(minLength: 20) }
        }
    }

    private func bubbleBody(_ message: ChatSessionModel.ChatMessage, text: String) -> some View {
        Group {
            if message.role == .user {
                Text(text)
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
            } else {
                ChatMarkdownView(markdown: text)
                    .font(.system(size: 12.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(message.role == .user ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10))
        )
    }

    private func bubbleText(_ message: ChatSessionModel.ChatMessage) -> String {
        message.isStreaming ? model.streamingDisplayText : message.text
    }

    private func attachmentsPreview(_ message: ChatSessionModel.ChatMessage) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(message.images.enumerated()), id: \.offset) { _, data in
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            ForEach(Array(message.fileNames.enumerated()), id: \.offset) { _, name in
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                    Text(name).font(.caption2).lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(5)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    /// 右下角拖拽手柄：调整弹窗尺寸。
    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(5)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.crosshair.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard let onResize else { return }
                        let dx = value.translation.width - lastDrag.width
                        let dy = value.translation.height - lastDrag.height
                        lastDrag = value.translation
                        onResize(CGSize(width: dx, height: dy))
                    }
                    .onEnded { _ in lastDrag = .zero }
            )
            .help("拖动调整窗口大小")
    }

    private func permissionBar(_ permission: ChatSessionModel.PendingPermission) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("需要授权")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(permission.title)
                .font(.callout)
                .lineLimit(3)
            HStack(spacing: 8) {
                ForEach(permission.options, id: \.optionId) { option in
                    Button(option.name ?? option.optionId) {
                        model.choosePermission(optionId: option.optionId)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
                Button("拒绝") { model.denyPermission() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(6)
    }

    // MARK: - 待发送附件

    private var attachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.attachments) { attachment in
                    attachmentChip(attachment)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func attachmentChip(_ attachment: ChatSessionModel.PendingAttachment) -> some View {
        HStack(spacing: 6) {
            if let data = attachment.previewData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "doc")
                    .frame(width: 26, height: 26)
            }
            Text(attachment.name)
                .font(.caption)
                .lineLimit(1)
            Button {
                model.removeAttachment(id: attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(6)
    }

    // MARK: - 命令联想

    private var commandSuggestions: [ACPCommand] {
        let text = model.input
        guard text.hasPrefix("/"), !text.contains(" ") else { return [] }
        let query = String(text.dropFirst()).lowercased()
        return Array(
            model.commands
                .filter { query.isEmpty || $0.name.lowercased().hasPrefix(query) }
                .prefix(8)
        )
    }

    private var commandBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commandSuggestions) { command in
                Button {
                    model.input = "/\(command.name) "
                    composerFocused = true
                } label: {
                    HStack(spacing: 8) {
                        Text("/\(command.name)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text(command.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let hint = command.inputHint, !hint.isEmpty {
                            Text(hint)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    private var noticeBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text(model.notice)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("知道了") { model.notice = "" }
                .buttonStyle(.link)
                .font(.caption)
        }
        .foregroundStyle(.orange)
    }

    // MARK: - @ 文件引用

    private var mentionQuery: String? {
        guard let at = model.input.range(of: "@", options: .backwards) else { return nil }
        let after = model.input[at.upperBound...]
        if after.contains(" ") || after.contains("\n") { return nil }
        let before = model.input[..<at.lowerBound]
        if let last = before.last, !last.isWhitespace { return nil }
        return String(after)
    }

    private var fileSuggestions: [String] {
        guard let query = mentionQuery else { return [] }
        return model.fileSuggestions(query: query)
    }

    private var fileBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(fileSuggestions, id: \.self) { path in
                Button {
                    insertMention(path)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(.caption)
                        Text(path)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    private func insertMention(_ path: String) {
        guard let at = model.input.range(of: "@", options: .backwards) else { return }
        model.input = String(model.input[..<at.lowerBound]) + "@" + path + " "
        composerFocused = true
    }

    // MARK: - 输入

    private func inputBar(maxComposerHeight: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            Button(action: openFilePicker) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("添加文件")
            .disabled(!isInteractive)

            ComposerTextView(
                text: $model.input,
                focused: $composerFocused,
                isEnabled: isInteractive,
                placeholder: "发消息…（Enter 发送，Shift+Enter 换行，可直接粘贴图片/文件）",
                maxHeight: maxComposerHeight,
                onSubmit: send,
                onPasteImage: handlePastedImage,
                onPasteFiles: handleFiles
            )

            if model.status == .running {
                circleButton(systemName: "stop.fill", enabled: true) { model.cancel() }
                    .help("停止")
            } else {
                circleButton(systemName: "arrow.up", enabled: model.canSend, action: send)
                    .help("发送")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    private func circleButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(enabled ? Color.accentColor : Color.secondary.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var isInteractive: Bool {
        switch model.status {
        case .ready, .running: return true
        default: return false
        }
    }

    private func send() {
        guard model.canSend else { return }
        model.send()
    }

    // MARK: - 附件处理

    private func handlePastedImage(_ data: Data) {
        guard let normalized = ImageAttachment.normalized(data) else {
            model.notice = "无法解析图片。"
            return
        }
        model.addImageAttachment(data: normalized.data, mimeType: normalized.mimeType, name: "粘贴的图片")
    }

    private func handleFiles(_ urls: [URL]) {
        for url in urls {
            let type = UTType(filenameExtension: url.pathExtension)
            if let type, type.conforms(to: .image),
               let data = try? Data(contentsOf: url),
               let normalized = ImageAttachment.normalized(data) {
                model.addImageAttachment(data: normalized.data, mimeType: normalized.mimeType, name: url.lastPathComponent)
            } else {
                model.addFileAttachment(url: url)
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            handleFiles(panel.urls)
        }
    }

    private var statusText: String {
        switch model.status {
        case .idle: return "未连接"
        case .starting: return "连接中…"
        case .ready: return "就绪"
        case .running: return "生成中…"
        case .failed: return "失败"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .ready: return .green
        case .running, .starting: return .yellow
        case .idle: return .gray
        case .failed: return .red
        }
    }
}
