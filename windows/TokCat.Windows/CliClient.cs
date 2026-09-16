using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace TokCat;

public sealed record SourceState(string Id, string Name, bool Enabled);

public sealed record Snapshot(double Rate, double TotalUnits, bool Currency, IReadOnlyList<SourceState> Sources)
{
    public static readonly Snapshot Empty = new(0, 0, false, Array.Empty<SourceState>());
}

public sealed record AgentCommand(string Name, string Description, string Hint);
public sealed record PermissionOption(string OptionId, string? Name, string? Kind);
public sealed record PermissionRequest(string Title, IReadOnlyList<PermissionOption> Options);
public sealed record AgentCapabilities(bool Image, bool EmbeddedContext);

public sealed class AgentEventArgs : EventArgs
{
    public string Kind { get; init; } = string.Empty;
    public string Text { get; init; } = string.Empty;
    public string? Title { get; init; }
    public string? Status { get; init; }
    public IReadOnlyList<AgentCommand> Commands { get; init; } = Array.Empty<AgentCommand>();
}

/// 发送内容块（属性名与 ACP 字段一致，由 System.Text.Json 序列化）。
public sealed class OutContent
{
    public string type { get; set; } = "text";
    public string? text { get; set; }
    public string? mimeType { get; set; }
    public string? data { get; set; }
    public string? uri { get; set; }
    public string? name { get; set; }
    public int? size { get; set; }
    public Dictionary<string, object?>? resource { get; set; }
}

/// <summary>
/// 与常驻 CLI（TokCatCli serve）通过 stdin/stdout 的 JSON-Lines 协议通信。
/// 最新快照以线程安全方式保存，UI 定时器读取，避免跨线程 marshal。
/// </summary>
public sealed class CliClient : IDisposable
{
    private readonly object _lock = new();
    private Process? _process;
    private int _nextId = 1;
    private Snapshot _latest = Snapshot.Empty;
    private volatile bool _running;

    public Snapshot Latest { get { lock (_lock) return _latest; } }
    public bool IsRunning => _running;
    public string? ResolvedPath { get; private set; }

    // MARK: - agent 事件

    public event EventHandler<AgentEventArgs>? AgentEventReceived;
    public event EventHandler<PermissionRequest>? AgentPermission;
    public event EventHandler<int>? AgentExit;
    public event EventHandler<string>? AgentFailed;
    public event EventHandler<(string SessionId, AgentCapabilities Capabilities)>? AgentReady;

    public static string? Locate()
    {
        // 优先使用自解压目录（单文件发布形态）。
        if (File.Exists(Payload.CliExe)) return Payload.CliExe;

        var local = Path.Combine(AppContext.BaseDirectory, "TokCatCli.exe");
        if (File.Exists(local)) return local;

        var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var dir in path.Split(Path.PathSeparator))
        {
            if (string.IsNullOrWhiteSpace(dir)) continue;
            var candidate = Path.Combine(dir, "TokCatCli.exe");
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }

    public bool Start()
    {
        var exe = Locate();
        if (exe is null) return false;
        ResolvedPath = exe;

        var psi = new ProcessStartInfo(exe, "serve")
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };

        try
        {
            var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
            proc.OutputDataReceived += (_, e) => { if (e.Data is not null) HandleLine(e.Data); };
            proc.ErrorDataReceived += (_, _) => { };
            proc.Exited += (_, _) => _running = false;

            if (!proc.Start()) return false;
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();

            _process = proc;
            _running = true;
            return true;
        }
        catch
        {
            return false;
        }
    }

    private void HandleLine(string line)
    {
        try
        {
            using var doc = JsonDocument.Parse(line);
            var root = doc.RootElement;
            if (!root.TryGetProperty("event", out var ev)) return;

            switch (ev.GetString() ?? string.Empty)
            {
                case "snapshot":
                    ParseSnapshot(root);
                    break;
                case "agent.ready":
                    ParseAgentReady(root);
                    break;
                case "agent.event":
                    ParseAgentEvent(root);
                    break;
                case "agent.permission":
                    ParseAgentPermission(root);
                    break;
                case "agent.failed":
                    AgentFailed?.Invoke(this, root.TryGetProperty("message", out var m) ? m.GetString() ?? string.Empty : string.Empty);
                    break;
                case "agent.exit":
                    AgentExit?.Invoke(this, root.TryGetProperty("code", out var c) ? c.GetInt32() : 0);
                    break;
            }
        }
        catch
        {
            // 忽略无法解析的行。
        }
    }

    private void ParseSnapshot(JsonElement root)
    {
        var rate = root.TryGetProperty("rate", out var r) ? r.GetDouble() : 0;
        var total = root.TryGetProperty("totalUnits", out var t) ? t.GetDouble() : 0;
        var currency = root.TryGetProperty("currency", out var c) && c.GetBoolean();

        var sources = new List<SourceState>();
        if (root.TryGetProperty("sources", out var arr) && arr.ValueKind == JsonValueKind.Array)
        {
            foreach (var s in arr.EnumerateArray())
            {
                sources.Add(new SourceState(
                    s.TryGetProperty("id", out var id) ? id.GetString() ?? string.Empty : string.Empty,
                    s.TryGetProperty("name", out var nm) ? nm.GetString() ?? string.Empty : string.Empty,
                    s.TryGetProperty("enabled", out var en) && en.GetBoolean()));
            }
        }

        lock (_lock) _latest = new Snapshot(rate, total, currency, sources);
    }

    private static bool Flag(JsonElement e, string name)
        => e.ValueKind != JsonValueKind.Undefined && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.True;

    private void ParseAgentReady(JsonElement root)
    {
        var sessionId = root.TryGetProperty("sessionId", out var s) ? s.GetString() ?? string.Empty : string.Empty;
        var caps = root.TryGetProperty("capabilities", out var c) ? c : default;
        var capabilities = new AgentCapabilities(Flag(caps, "image"), Flag(caps, "embeddedContext"));
        AgentReady?.Invoke(this, (sessionId, capabilities));
    }

    private void ParseAgentEvent(JsonElement root)
    {
        var kind = root.TryGetProperty("kind", out var k) ? k.GetString() ?? string.Empty : string.Empty;
        var args = new AgentEventArgs { Kind = kind };

        switch (kind)
        {
            case "text":
            case "thought":
                args = args with { Text = root.TryGetProperty("text", out var t) ? t.GetString() ?? string.Empty : string.Empty };
                break;
            case "tool":
                args = args with { Title = root.TryGetProperty("title", out var ti) ? ti.GetString() : null };
                break;
            case "toolUpdate":
                args = args with
                {
                    Title = root.TryGetProperty("title", out var ti2) ? ti2.GetString() : null,
                    Status = root.TryGetProperty("status", out var st) ? st.GetString() : null,
                };
                break;
            case "plan":
                var entries = new List<string>();
                if (root.TryGetProperty("entries", out var pe) && pe.ValueKind == JsonValueKind.Array)
                {
                    entries.AddRange(pe.EnumerateArray().Select(x => x.GetString() ?? string.Empty));
                }
                args = args with { Text = string.Join("\n", entries) };
                break;
            case "commands":
                var cmds = new List<AgentCommand>();
                if (root.TryGetProperty("commands", out var ca) && ca.ValueKind == JsonValueKind.Array)
                {
                    foreach (var c in ca.EnumerateArray())
                    {
                        cmds.Add(new AgentCommand(
                            c.TryGetProperty("name", out var n) ? n.GetString() ?? string.Empty : string.Empty,
                            c.TryGetProperty("description", out var de) ? de.GetString() ?? string.Empty : string.Empty,
                            c.TryGetProperty("hint", out var h) ? h.GetString() : null));
                    }
                }
                args = args with { Commands = cmds };
                break;
        }

        AgentEventReceived?.Invoke(this, args);
    }

    private void ParseAgentPermission(JsonElement root)
    {
        var title = root.TryGetProperty("title", out var t) ? t.GetString() ?? "需要授权" : "需要授权";
        var options = new List<PermissionOption>();
        if (root.TryGetProperty("options", out var arr) && arr.ValueKind == JsonValueKind.Array)
        {
            foreach (var o in arr.EnumerateArray())
            {
                options.Add(new PermissionOption(
                    o.TryGetProperty("optionId", out var id) ? id.GetString() ?? string.Empty : string.Empty,
                    o.TryGetProperty("name", out var nm) ? nm.GetString() : null,
                    o.TryGetProperty("kind", out var kd) ? kd.GetString() : null));
            }
        }
        AgentPermission?.Invoke(this, new PermissionRequest(title, options));
    }

    public void Send(string cmd, object? parameters = null)
    {
        var proc = _process;
        if (proc is null || proc.HasExited) return;

        var payload = new Dictionary<string, object?> { ["id"] = _nextId++, ["cmd"] = cmd };
        if (parameters is not null) payload["params"] = parameters;

        try
        {
            proc.StandardInput.WriteLine(JsonSerializer.Serialize(payload));
            proc.StandardInput.Flush();
        }
        catch
        {
            // 忽略写入失败。
        }
    }

    // MARK: - agent 命令

    public void AgentConnect(string mode, string cwd, object? remote = null)
        => Send("agent.connect", new { mode, cwd, remote });

    public void AgentPrompt(IReadOnlyList<object> content)
        => Send("agent.prompt", new { content });

    public void AgentCancel() => Send("agent.cancel");

    public void AgentPermissionReply(string? optionId)
        => Send("agent.permission.reply", new { optionId });

    public void AgentDisconnect() => Send("agent.disconnect");

    public void Dispose()
    {
        try
        {
            Send("quit");
            if (_process is { } p && !p.HasExited && !p.WaitForExit(1500))
            {
                p.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // 忽略退出异常。
        }
        _process?.Dispose();
        _process = null;
    }
}
