import SwiftUI
import TokCatAgent

/// Agent 检测 / 一键安装窗口。
struct AgentSetupView: View {
    @ObservedObject var model: AgentSetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent 检测与安装")
                .font(.headline)
            Text("TokCat 通过 ACP 协议接入 agent。未安装的可一键安装，装好后用终端完成登录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(model.rows) { row in
                rowView(row)
                Divider()
            }

            customCommandRow
            logView

            HStack {
                Button("重新检测") { model.refresh() }
                Spacer()
                ProgressView().controlSize(.small).opacity(model.busy ? 1 : 0)
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 520)
    }

    private func rowView(_ row: AgentSetupModel.Row) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.installed ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(row.installed ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.preset.displayName).font(.body)
                Text(row.path ?? (row.preset.id == AgentPreset.customID ? "在下方填写自定义命令" : "未安装"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if row.preset.installCommand != nil, !row.installed {
                Button("一键安装") { model.install(row.preset) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.busy)
            }
            if row.preset.loginCommand != nil {
                Button("登录") { model.openLogin(row.preset) }
                    .controlSize(.small)
            }
            if row.preset.docsURL != nil {
                Button("文档") { model.openDocs(row.preset) }
                    .controlSize(.small)
            }
        }
    }

    private var customCommandRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("自定义命令").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("如 npx @zed-industries/claude-agent-acp", text: $model.customCommand)
                    .textFieldStyle(.roundedBorder)
                Button("保存") { model.saveCustomCommand() }
                    .controlSize(.small)
            }
        }
    }

    private var logView: some View {
        ScrollView {
            Text(model.log.isEmpty ? "安装日志会显示在这里。" : model.log)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 150)
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
    }
}
