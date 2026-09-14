import Foundation

/// 通过登入 shell 执行命令并流式回传输出（用于一键安装）。
public enum ShellRunner {
    @discardableResult
    public static func run(
        _ command: String,
        environment: [String: String]? = nil,
        onOutput: @escaping @Sendable (String) -> Void,
        onFinish: @escaping @Sendable (Int32) -> Void
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        if let environment {
            process.environment = environment
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            onOutput(String(decoding: data, as: UTF8.self))
        }

        process.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            if !rest.isEmpty {
                onOutput(String(decoding: rest, as: UTF8.self))
            }
            onFinish(proc.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            onOutput("启动失败：\(error.localizedDescription)\n")
            onFinish(-1)
        }
        return process
    }
}
