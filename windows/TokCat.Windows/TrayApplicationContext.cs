using System.Drawing;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace TokCat;

/// <summary>托盘应用：通知区图标动画 + 右键菜单，速率来自常驻 CLI。</summary>
public sealed class TrayApplicationContext : ApplicationContext
{
    private static readonly (string Id, string Label)[] Metrics =
    {
        ("weighted", "加权 token"),
        ("total", "全部 token"),
        ("inputOutput", "仅 input + output"),
        ("cost", "金额 (USD, models.dev)"),
    };

    private static readonly double[] Sizes = { 16, 18, 20, 22, 24 };
    private static readonly double[] FpsOptions = { 10, 20, 30, 40 };
    private static readonly double[] Sensitivities = { 0.25, 0.5, 1.0, 2.0, 4.0 };

    private readonly AppSettings _settings;
    private readonly AnimationPack _pack;
    private readonly CliClient _cli;
    private readonly NotifyIcon _tray;
    private readonly ContextMenuStrip _menu;
    private readonly System.Windows.Forms.Timer _frameTimer;
    private readonly System.Windows.Forms.Timer _snapshotTimer;
    private readonly HashSet<string> _appliedOverrides = new();

    private StatusForm? _statusForm;
    private readonly Control _marshal = new Control();
    private EventWaitHandle? _activateEvent;

    private Snapshot _snapshot = Snapshot.Empty;
    private double _rate;
    private bool _currency;

    private int _frameIndex;
    private int _frameBaseIndex;
    private DateTime _frameBaseTime = DateTime.UtcNow;
    private double _lastInterval;

    public TrayApplicationContext()
    {
        _settings = AppSettings.Load();
        _pack = new AnimationPack();

        _tray = new NotifyIcon { Visible = true, Text = "TokCat" };
        _menu = new ContextMenuStrip();
        _menu.Opening += (_, _) => RebuildMenu();
        _tray.ContextMenuStrip = _menu;
        _tray.MouseClick += OnTrayMouseClick;

        // 单实例：在 UI 线程建好 marshal 句柄，并监听第二个实例的激活信号。
        _ = _marshal.Handle;
        StartActivationListener();

        _cli = new CliClient();
        if (!_cli.Start())
        {
            _tray.BalloonTipTitle = "TokCat";
            _tray.BalloonTipText = "未找到 TokCatCli.exe，无法读取 token 速率。";
            _tray.ShowBalloonTip(4000);
        }

        _frameTimer = new System.Windows.Forms.Timer { Interval = 16 };
        _frameTimer.Tick += (_, _) => AdvanceFrame();
        _frameTimer.Start();

        _snapshotTimer = new System.Windows.Forms.Timer { Interval = 200 };
        _snapshotTimer.Tick += (_, _) => PullSnapshot();
        _snapshotTimer.Start();

        Render();
    }

    // MARK: - 快照 / 渲染

    private void PullSnapshot()
    {
        var latest = _cli.Latest;
        if (!ReferenceEquals(latest, _snapshot))
        {
            _snapshot = latest;
            _rate = latest.Rate;
            _currency = latest.Currency;
            _statusForm?.UpdateSnapshot(latest);
            Render();
        }

        // 首次拿到来源列表后，把本地保存的开关同步给 CLI。
        foreach (var source in latest.Sources)
        {
            if (_appliedOverrides.Contains(source.Id)) continue;
            _appliedOverrides.Add(source.Id);
            if (_settings.SourceOverrides.TryGetValue(source.Id, out var enabled))
            {
                _cli.Send("source", new { id = source.Id, enabled });
            }
        }
    }

    private void AdvanceFrame()
    {
        if (_pack.FrameCount == 0) return;

        var progress = _rate <= 0
            ? 0
            : Math.Min(Math.Max(_rate * _settings.Sensitivity / _settings.SaturationRate, 0), 1);
        var fps = _settings.IdleFps + (_settings.MaxFps - _settings.IdleFps) * progress;
        if (fps <= 0) fps = 1;
        var interval = 1.0 / fps;

        var now = DateTime.UtcNow;
        if (Math.Abs(interval - _lastInterval) > 0.0005)
        {
            _frameBaseIndex = _frameIndex;
            _frameBaseTime = now;
            _lastInterval = interval;
        }

        var elapsed = (now - _frameBaseTime).TotalSeconds;
        var advance = (int)Math.Floor(elapsed / interval);
        var count = _pack.FrameCount;
        var newIndex = ((_frameBaseIndex + advance) % count + count) % count;
        if (newIndex == _frameIndex) return;

        _frameIndex = newIndex;
        Render();
    }

    private void Render()
    {
        var icon = _pack.GetFrame(_frameIndex, (int)Math.Round(_settings.IconSize), TintColor());
        if (icon is not null) _tray.Icon = icon;
        _tray.Text = Truncate($"TokCat · {Formatting.Rate(_rate, _currency)}", 63);
    }

    private static string Truncate(string value, int max)
        => value.Length <= max ? value : value[..max];

    private static Color TintColor()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            if (key?.GetValue("SystemUsesLightTheme") is int light)
            {
                return light != 0 ? Color.FromArgb(30, 30, 30) : Color.White;
            }
        }
        catch
        {
            // 读取失败时用深色。
        }
        return Color.FromArgb(30, 30, 30);
    }

    // MARK: - 交互

    private void OnTrayMouseClick(object? sender, MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left) ToggleStatusForm();
    }

    private void ToggleStatusForm()
    {
        if (_statusForm is { Visible: true })
        {
            _statusForm.Hide();
            return;
        }

        _statusForm ??= new StatusForm();
        _statusForm.UpdateSnapshot(_snapshot);
        var cursor = Cursor.Position;
        _statusForm.Location = new Point(cursor.X - 140, Math.Max(0, cursor.Y - 220));
        _statusForm.Show();
        _statusForm.Activate();
    }

    // MARK: - 单实例激活

    private const string ActivateEventName = "TokCat.SingleInstance.Activate";

    private void StartActivationListener()
    {
        try
        {
            _activateEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ActivateEventName);
        }
        catch
        {
            return;
        }

        var thread = new Thread(() =>
        {
            var handle = _activateEvent;
            if (handle is null) return;
            while (true)
            {
                try
                {
                    if (!handle.WaitOne()) continue;
                }
                catch
                {
                    return;
                }
                try { _marshal.BeginInvoke(new Action(ActivateFromExternal)); } catch { }
            }
        })
        { IsBackground = true, Name = "tokcat.activate" };
        thread.Start();
    }

    /// <summary>第二个实例请求激活：显示主窗口（Chat，暂为状态窗）。</summary>
    private void ActivateFromExternal()
    {
        if (_statusForm is { Visible: true })
        {
            _statusForm.Activate();
            return;
        }
        ToggleStatusForm();
    }

    // MARK: - 菜单

    private void RebuildMenu()
    {
        _menu.Items.Clear();

        _menu.Items.Add(new ToolStripMenuItem(
            $"速率 {Formatting.Rate(_rate, _currency)} · 合计 {Formatting.Units(_snapshot.TotalUnits, _currency)}")
        { Enabled = false });
        _menu.Items.Add(new ToolStripSeparator());

        _menu.Items.Add(MetricMenu());
        _menu.Items.Add(SizeMenu());
        _menu.Items.Add(MaxFpsMenu());
        _menu.Items.Add(SensitivityMenu());
        _menu.Items.Add(SourcesMenu());

        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(Item("重载模型定价", (_, _) => _cli.Send("reloadPricing")));
        _menu.Items.Add(Item("重置统计", (_, _) => _cli.Send("reset")));

        _menu.Items.Add(new ToolStripSeparator());
        var autostart = new ToolStripMenuItem("开机自启") { Checked = Autostart.IsEnabled() };
        autostart.Click += (_, _) => Autostart.SetEnabled(!Autostart.IsEnabled());
        _menu.Items.Add(autostart);

        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(Item("退出 TokCat", (_, _) => ExitApp()));
    }

    private ToolStripMenuItem MetricMenu()
    {
        var parent = new ToolStripMenuItem("速率口径");
        foreach (var (id, label) in Metrics)
        {
            var item = new ToolStripMenuItem(label) { Checked = id == _settings.MetricKind };
            item.Click += (_, _) =>
            {
                _settings.MetricKind = id;
                _settings.Save();
                _cli.Send("metric", new { metric = id });
            };
            parent.DropDownItems.Add(item);
        }
        return parent;
    }

    private ToolStripMenuItem SizeMenu()
    {
        var parent = new ToolStripMenuItem("尺寸");
        foreach (var size in Sizes)
        {
            var item = new ToolStripMenuItem($"{(int)size} pt") { Checked = Math.Abs(size - _settings.IconSize) < 0.001 };
            item.Click += (_, _) =>
            {
                _settings.IconSize = size;
                _settings.Save();
                Render();
            };
            parent.DropDownItems.Add(item);
        }
        return parent;
    }

    private ToolStripMenuItem MaxFpsMenu()
    {
        var parent = new ToolStripMenuItem("最大帧率");
        foreach (var fps in FpsOptions)
        {
            var item = new ToolStripMenuItem($"{(int)fps} fps") { Checked = Math.Abs(fps - _settings.MaxFps) < 0.001 };
            item.Click += (_, _) =>
            {
                _settings.MaxFps = fps;
                _settings.Save();
            };
            parent.DropDownItems.Add(item);
        }
        return parent;
    }

    private ToolStripMenuItem SensitivityMenu()
    {
        var parent = new ToolStripMenuItem("灵敏度");
        foreach (var value in Sensitivities)
        {
            var item = new ToolStripMenuItem($"{value}×") { Checked = Math.Abs(value - _settings.Sensitivity) < 0.001 };
            item.Click += (_, _) =>
            {
                _settings.Sensitivity = value;
                _settings.Save();
            };
            parent.DropDownItems.Add(item);
        }
        return parent;
    }

    private ToolStripMenuItem SourcesMenu()
    {
        var parent = new ToolStripMenuItem("数据源");
        if (_snapshot.Sources.Count == 0)
        {
            parent.DropDownItems.Add(new ToolStripMenuItem("（等待 CLI…）") { Enabled = false });
            return parent;
        }

        foreach (var source in _snapshot.Sources)
        {
            var item = new ToolStripMenuItem(source.Name) { Checked = source.Enabled };
            item.Click += (_, _) =>
            {
                var enabled = !source.Enabled;
                _settings.SetEnabled(source.Id, enabled);
                _cli.Send("source", new { id = source.Id, enabled });
            };
            parent.DropDownItems.Add(item);
        }
        return parent;
    }

    private static ToolStripMenuItem Item(string text, EventHandler onClick)
    {
        var item = new ToolStripMenuItem(text);
        item.Click += onClick;
        return item;
    }

    // MARK: - 退出

    private void ExitApp()
    {
        _frameTimer.Stop();
        _snapshotTimer.Stop();
        _tray.Visible = false;
        _tray.Dispose();
        _cli.Dispose();
        _pack.Dispose();
        _statusForm?.Dispose();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _frameTimer.Dispose();
            _snapshotTimer.Dispose();
            _tray.Dispose();
            _cli.Dispose();
            _pack.Dispose();
            _statusForm?.Dispose();
            _activateEvent?.Dispose();
            _marshal.Dispose();
        }
        base.Dispose(disposing);
    }
}
