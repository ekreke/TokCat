import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TokCatAgent

/// Chat 弹窗：输入 + 流式回答（只显示最新回答，Markdown 渲染）。
struct ChatView: View {
    @ObservedObject var model: ChatSessionModel
    /// 未安装 agent 时点击“安装 / 设置”。
    var onSetup: (() -> Void)?
    /// 右下角拖拽手柄的尺寸增量回调（由控制器换算成弹窗尺寸）。
    var onResize: ((CGSize) -> Void)?
    @State private var composerFocused = true
    @State private var lastDrag: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            output
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
            inputBar
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) { resizeHandle }
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

    private var output: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if case let .failed(message) = model.status {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.answer.isEmpty, model.displayAnswer.isEmpty {
                    Text(model.activity.isEmpty ? "问点什么吧。" : model.activity)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ChatMarkdownView(markdown: model.displayAnswer)
                        .font(.system(size: 12.5))
                }
                if !model.answer.isEmpty, !model.activity.isEmpty {
                    Text(model.activity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
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

    // MARK: - 附件

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

    // MARK: - 输入

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button(action: pasteClipboardImage) {
                Image(systemName: "photo.on.rectangle")
            }
            .buttonStyle(.borderless)
            .help(model.imageSupported ? "粘贴剪贴板图片" : "当前 agent 未声明图片输入能力")
            .disabled(!isInteractive)

            Button(action: openFilePicker) {
                Image(systemName: "paperclip")
            }
            .buttonStyle(.borderless)
            .help("添加文件")
            .disabled(!isInteractive)

            ComposerTextView(
                text: $model.input,
                focused: $composerFocused,
                isEnabled: isInteractive,
                onSubmit: send,
                onPasteImage: handlePastedImage,
                onPasteFiles: handleFiles
            )
            .frame(minHeight: 34)
            .overlay(alignment: .topLeading) {
                if model.input.isEmpty {
                    Text("发消息…（Enter 发送，Shift+Enter 换行，可直接粘贴图片/文件）")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
            }

            if model.status == .running {
                Button("停止") { model.cancel() }
                    .buttonStyle(.bordered)
            } else {
                Button("发送", action: send)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSend)
            }
        }
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

    private func pasteClipboardImage() {
        guard let data = PasteAwareTextView.imageData(from: .general) else {
            model.notice = "剪贴板里没有图片。"
            return
        }
        handlePastedImage(data)
    }

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
