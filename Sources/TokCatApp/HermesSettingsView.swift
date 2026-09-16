import SwiftUI
import TokCatAgent

/// Hermes 设置窗口（本地 / 远程 SSH）。
struct HermesSettingsView: View {
    @ObservedObject var model: HermesSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hermes 设置")
                .font(.headline)
            Text("TokCat 通过 ACP 协议接入 Hermes。可连本机，也可通过 SSH 连服务器上的 Hermes。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $model.mode) {
                ForEach(HermesMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.mode == .local {
                        localSection
                    } else {
                        remoteSection
                    }

                    workingDirectoryRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            logView

            HStack {
                Button("保存") { model.save() }
                    .buttonStyle(.borderedProminent)
                Spacer()
                ProgressView().controlSize(.small).opacity(model.busy ? 1 : 0)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 520)
    }

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.localPath != nil ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(model.localPath != nil ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("本地 Hermes").font(.body)
                    Text(model.localPath ?? "未安装")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if model.localPath == nil {
                    Button("一键安装") { model.installLocal() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(model.busy)
                }
                Button("登录") { model.openLocalLogin() }
                    .controlSize(.small)
                Button("文档") { model.openLocalDocs() }
                    .controlSize(.small)
                Button("重新检测") { model.refreshLocal() }
                    .controlSize(.small)
            }
        }
    }

    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("SSH 目标", text: $model.sshTarget, placeholder: "user@host 或 ~/.ssh/config 别名（如 be-tools）")
            HStack(spacing: 12) {
                field("端口", text: $model.sshPortText, placeholder: "留空默认 22")
                field("私钥", text: $model.sshIdentityFile, placeholder: "~/.ssh/id_ed25519")
            }
            field("远程命令", text: $model.remoteCommand, placeholder: "hermes acp")
            HStack(spacing: 12) {
                field("登录 shell 包装", text: $model.remoteLoginShell, placeholder: "留空直接执行，如 zsh -lic")
                field("远程工作目录", text: $model.remoteWorkingDirectory, placeholder: "留空 = 远端 home")
            }
            VStack(alignment: .leading, spacing: 4) {
                Button("测试连接") { model.testRemoteConnection() }
                    .controlSize(.small)
                    .disabled(model.busy)
                Text("运行 `ssh <目标> \"hermes acp --check\"`，用于验证网络与 PATH。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var workingDirectoryRow: some View {
        field(
            model.mode == .local ? "本地工作目录" : "本地进程目录",
            text: $model.localWorkingDirectory,
            placeholder: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            // 不用 SwiftUI TextField：其 field editor 在 macOS 15.2 上点按/拖选
            // 会触发 TextKit 2 同步死循环（详见 SingleLineTextField 头注释）。
            SingleLineTextField(text: text, placeholder: placeholder)
                .frame(height: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var logView: some View {
        ReadOnlyLogTextView(text: model.log)
            .frame(height: 150)
    }
}
