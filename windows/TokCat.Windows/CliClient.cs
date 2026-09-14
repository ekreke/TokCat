using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace TokCat;

public sealed record SourceState(string Id, string Name, bool Enabled);

public sealed record Snapshot(double Rate, double TotalUnits, bool Currency, IReadOnlyList<SourceState> Sources)
{
    public static readonly Snapshot Empty = new(0, 0, false, Array.Empty<SourceState>());
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

    public static string? Locate()
    {
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
            if (!root.TryGetProperty("event", out var ev) || ev.GetString() != "snapshot") return;

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
        catch
        {
            // 忽略无法解析的行。
        }
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
