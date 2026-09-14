import SwiftUI
import TokCatAgent

/// Chat 弹窗：输入 + 流式回答（只显示最新回答）。
struct ChatView: View {
    @ObservedObject var model: ChatSessionModel
    /// 未安装 agent 时点击“安装 / 设置”。
    var onSetup: (() -> Void)?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            output
            if let permission = model.pendingPermission {
                permissionBar(permission)
            }
            inputBar
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { inputFocused = true }
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
                } else if model.answer.isEmpty {
                    Text(model.activity.isEmpty ? "问点什么吧。" : model.activity)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.answer)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !model.answer.isEmpty, !model.activity.isEmpty {
                    Text(model.activity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 220)
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

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("发消息…", text: $model.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
                .disabled(!isInteractive)

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
