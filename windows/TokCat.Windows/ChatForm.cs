using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Text;
using System.Windows.Forms;
using Microsoft.Web.WebView2.WinForms;

namespace TokCat;

/// <summary>
/// Windows 版 Chat：左键托盘打开；对话区用 WebView2 渲染 Markdown，
/// 输入条为 Gemini 风格（+ 附件、圆形发送）；数据经 CLI 的 ACP 协议。
/// </summary>
public sealed class ChatForm : Form
{
    private const string ShellHtml = """
<!doctype html>
<html><head><meta charset="utf-8"><style>
body{margin:0;padding:10px;font-family:'Segoe UI',sans-serif;font-size:13px;background:transparent;color:#e0e0e0;}
.msg{margin:6px 0;padding:8px 10px;border-radius:10px;max-width:92%;box-sizing:border-box;}
.user{background:#2f4470;margin-left:auto;}
.agent{background:#333;margin-right:auto;}
.txt{white-space:pre-wrap;word-break:break-word;}
.attach{margin-top:4px;display:flex;gap:6px;flex-wrap:wrap;}
.attach img{width:44px;height:44px;object-fit:cover;border-radius:6px;}
.attach .file{font-size:11px;color:#aaa;border:1px solid #555;border-radius:5px;padding:2px 6px;}
pre{background:#191919;padding:8px;border-radius:6px;overflow-x:auto;}
code{font-family:Consolas,monospace;}
p code,li code{background:#191919;padding:1px 4px;border-radius:4px;}
a{color:#7fb3ff;}
ul,ol{margin:4px 0;padding-left:20px;}
h1,h2,h3,h4{margin:8px 0 4px;}
</style></head>
<body><div id="root"></div>
<script>
function addMsg(role, html){var d=document.createElement('div');d.className='msg '+(role==='user'?'user':'agent');d.id='last';d.innerHTML=html;root().appendChild(d);scroll();}
function updateLastAgent(html){var d=document.getElementById('last');if(d){d.innerHTML=html;}scroll();}
function scroll(){window.scrollTo(0,document.body.scrollHeight);}
</script></body></html>
""";

    private readonly CliClient _cli;
    private readonly AppSettings _settings;

    private readonly WebView2 _web = new() { Dock = DockStyle.Fill };
    private readonly TextBox _fallback = new()
    {
        Dock = DockStyle.Fill,
        Multiline = true,
        ReadOnly = true,
        ScrollBars = ScrollBars.Vertical,
        BackColor = Color.FromArgb(24, 24, 24),
        ForeColor = Color.Gainsboro,
        BorderStyle = BorderStyle.None,
    };
    private readonly PasteAwareTextBox _input = new()
    {
        Dock = DockStyle.Fill,
        BorderStyle = BorderStyle.None,
        BackColor = Color.FromArgb(22, 22, 22),
        ForeColor = Color.Gainsboro,
        Font = new Font("Segoe UI", 10f),
    };
    private readonly Panel _box = new();
    private readonly Panel _inputPanel = new();
    private readonly Panel _permissionPanel = new();
    private readonly FlowLayoutPanel _attachmentPanel = new();
    private readonly ListBox _commandList = new();
    private readonly Button _sendButton = new();
    private readonly Button _attachButton = new();
    private readonly System.Windows.Forms.Timer _renderTimer = new() { Interval = 150 };

    private readonly List<AgentCommand> _commands = new();
    private readonly List<OutContent> _attachments = new();
    private readonly StringBuilder _streaming = new();
    private readonly List<string> _pendingScripts = new();

    private bool _imageSupported;
    private bool _embeddedContextSupported;
    private bool _webReady;
    private bool _shellLoaded;
    private bool _running;
    private bool _connected;
    private string _agentName = "Hermes";

    public ChatForm(CliClient cli, AppSettings settings)
    {
        _cli = cli;
        _settings = settings;

        Text = "TokCat Chat";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(430, 560);
        Font = new Font("Segoe UI", 9.5f);
        BackColor = Color.FromArgb(24, 24, 24);
        AllowDrop = true;

        BuildUi();
        WireCli();
        WireInput();

        _renderTimer.Tick += (_, _) => FlushStreaming();
        _renderTimer.Start();

        Load += async (_, _) =>
        {
            _ = Handle;
            await InitWebAsync();
            _cli.AgentConnect("local", _settings.AgentWorkingDirectory);
        };
    }

    // MARK: - UI 构建

    private void BuildUi()
    {
        _web.CoreWebView2InitializationCompleted += (_, e) =>
        {
            if (!e.IsSuccess) return;
            _web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            _web.CoreWebView2.Settings.IsStatusBarEnabled = false;
            _web.CoreWebView2.NavigationCompleted += (_, _) =>
            {
                _shellLoaded = true;
                foreach (var js in _pendingScripts)
                {
                    _ = _web.CoreWebView2.ExecuteScriptAsync(js);
                }
                _pendingScripts.Clear();
            };
        };

        _permissionPanel.Dock = DockStyle.Top;
        _permissionPanel.Height = 56;
        _permissionPanel.Visible = false;
        _permissionPanel.BackColor = Color.FromArgb(48, 38, 18);
        _permissionPanel.Padding = new Padding(6);

        _attachmentPanel.Dock = DockStyle.Top;
        _attachmentPanel.AutoSize = true;
        _attachmentPanel.WrapContents = false;
        _attachmentPanel.Visible = false;
        _attachmentPanel.Padding = new Padding(6, 2, 6, 2);

        _box.Dock = DockStyle.Fill;
        _box.BackColor = Color.FromArgb(22, 22, 22);
        _box.Padding = new Padding(2);
        _box.Controls.Add(_input);
        _box.Paint += (_, e) => e.Graphics.DrawRectangle(new Pen(Color.FromArgb(90, 90, 90)), 0, 0, _box.Width - 1, _box.Height - 1);

        _attachButton.Text = "+";
        _attachButton.Width = 32;
        _attachButton.Height = 32;
        _attachButton.FlatStyle = FlatStyle.Flat;
        _attachButton.FlatAppearance.BorderSize = 0;
        _attachButton.BackColor = Color.FromArgb(50, 50, 50);
        _attachButton.ForeColor = Color.Gainsboro;
        _attachButton.Click += (_, _) => openFilePicker();
        MakeCircle(_attachButton);

        _sendButton.Width = 32;
        _sendButton.Height = 32;
        _sendButton.FlatStyle = FlatStyle.Flat;
        _sendButton.FlatAppearance.BorderSize = 0;
        _sendButton.BackColor = Color.FromArgb(70, 110, 220);
        _sendButton.ForeColor = Color.White;
        _sendButton.Click += (_, _) => send();
        MakeCircle(_sendButton);

        var grid = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 1,
        };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        grid.Controls.Add(_attachButton, 0, 0);
        grid.Controls.Add(_box, 1, 0);
        grid.Controls.Add(_sendButton, 2, 0);

        _inputPanel.Dock = DockStyle.Bottom;
        _inputPanel.Height = 54;
        _inputPanel.Padding = new Padding(6);
        _inputPanel.BackColor = Color.FromArgb(30, 30, 30);
        _inputPanel.Controls.Add(grid);

        Controls.Add(_web);
        Controls.Add(_fallback);
        Controls.Add(_attachmentPanel);
        Controls.Add(_permissionPanel);
        Controls.Add(_inputPanel);
        Controls.Add(_commandList);

        _web.BringToFront();
        _fallback.BringToFront();
        _attachmentPanel.BringToFront();
        _permissionPanel.BringToFront();
        _inputPanel.BringToFront();
        _commandList.BringToFront();
        _commandList.Visible = false;

        DragEnter += (_, e) => { if (e.Data?.GetDataPresent(DataFormats.FileDrop) == true) e.Effect = DragDropEffects.Copy; };
        DragDrop += (_, e) =>
        {
            if (e.Data?.GetData(DataFormats.FileDrop) is string[] files && files.Length > 0)
            {
                HandleFiles(files);
            }
        };
    }

    private static void MakeCircle(Control control)
    {
        control.Resize += (_, _) =>
        {
            using var path = new GraphicsPath();
            path.AddEllipse(0, 0, control.Width - 1, control.Height - 1);
            control.Region = new Region(path);
        };
    }

    // MARK: - WebView / 渲染

    private async Task InitWebAsync()
    {
        try
        {
            await _web.EnsureCoreWebView2Async();
            _web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            _web.CoreWebView2.Settings.IsStatusBarEnabled = false;
            _web.CoreWebView2.NavigationCompleted += (_, _) =>
            {
                _shellLoaded = true;
                foreach (var js in _pendingScripts)
                {
                    _ = _web.CoreWebView2.ExecuteScriptAsync(js);
                }
                _pendingScripts.Clear();
            };
            _web.CoreWebView2.NavigateToString(ShellHtml);
            _webReady = true;
        }
        catch (Exception ex)
        {
            _web.Visible = false;
            _fallback.Visible = true;
            _fallback.Text = "WebView2 不可用，已切换纯文本视图：" + ex.Message;
        }
    }

    private void Exec(string js)
    {
        if (!_webReady) return;
        if (!_shellLoaded)
        {
            _pendingScripts.Add(js);
            return;
        }
        _ = _web.CoreWebView2.ExecuteScriptAsync(js);
    }

    private static string Quote(string value) => JsonSerializer.Serialize(value);

    private void AddUserMessage(string text, IReadOnlyList<byte[]> images, IReadOnlyList<string> fileNames)
    {
        var sb = new StringBuilder();
        if (!string.IsNullOrWhiteSpace(text))
        {
            sb.Append("<div class=\"txt\">").Append(System.Net.WebUtility.HtmlEncode(text)).Append("</div>");
        }
        if (images.Count > 0 || fileNames.Count > 0)
        {
            sb.Append("<div class=\"attach\">");
            foreach (var data in images)
            {
                sb.Append("<img src=\"data:image/png;base64,").Append(Convert.ToBase64String(data)).Append("\"/>");
            }
            foreach (var name in fileNames)
            {
                sb.Append("<span class=\"file\">").Append(System.Net.WebUtility.HtmlEncode(name)).Append("</span>");
            }
            sb.Append("</div>");
        }
        Exec($"addMsg('user', {Quote(sb.ToString())})");
    }

    private void UpdateStreamingAgent(string text)
    {
        Exec($"updateLastAgent({Quote("<div class=\"txt\">" + System.Net.WebUtility.HtmlEncode(text) + "</div>")})");
    }

    private void UpdateFinalAgent(string markdown)
    {
        Exec($"updateLastAgent({Quote(MarkdownRenderer.ToHtml(markdown))})");
    }

    private void AddSystemMessage(string message)
    {
        Exec($"addMsg('agent', {Quote("<div class=\"txt\">" + System.Net.WebUtility.HtmlEncode(message) + "</div>")})");
    }

    // MARK: - agent 事件

    private void WireCli()
    {
        _cli.AgentEventReceived += (_, e) => Ui(() => OnAgentEvent(e));
        _cli.AgentPermission += (_, p) => Ui(() => ShowPermission(p));
        _cli.AgentFailed += (_, msg) => Ui(() => { AddSystemMessage(msg); });
        _cli.AgentExit += (_, code) => Ui(() =>
        {
            _running = false;
            UpdateSendState();
            AddSystemMessage($"agent 已退出（{code}）");
        });
        _cli.AgentReady += (_, ready) => Ui(() => OnAgentReady(ready.SessionId, ready.Capabilities));
    }

    private void OnAgentReady(string sessionId, AgentCapabilities capabilities)
    {
        _connected = true;
        _imageSupported = capabilities.Image;
        _embeddedContextSupported = capabilities.EmbeddedContext;
        UpdateSendState();
        AddSystemMessage($"{_agentName} 已连接（图片：{(_imageSupported ? "支持" : "不支持")}）。");
    }

    private void OnAgentEvent(AgentEventArgs e)
    {
        switch (e.Kind)
        {
            case "text":
                _streaming.Append(e.Text);
                break;
            case "thought":
                break;
            case "commands":
                _commands.Clear();
                _commands.AddRange(e.Commands);
                break;
        }
    }

    private void FlushStreaming()
    {
        if (_streaming.Length == 0) return;
        UpdateStreamingAgent(_streaming.ToString());
    }

    private void ShowPermission(PermissionRequest request)
    {
        _permissionPanel.Controls.Clear();
        _permissionPanel.Height = 56;
        _permissionPanel.Visible = true;

        var label = new Label
        {
            Text = request.Title,
            AutoSize = true,
            Location = new Point(6, 6),
            ForeColor = Color.Orange,
            MaximumSize = new Size(_permissionPanel.Width - 12, 0),
        };
        _permissionPanel.Controls.Add(label);

        var x = 6;
        var y = 28;
        foreach (var option in request.Options)
        {
            var button = new Button
            {
                Text = option.Name ?? option.OptionId,
                AutoSize = true,
                Location = new Point(x, y),
                FlatStyle = FlatStyle.Flat,
            };
            var optionId = option.OptionId;
            button.Click += (_, _) =>
            {
                _cli.AgentPermissionReply(optionId);
                _permissionPanel.Visible = false;
            };
            _permissionPanel.Controls.Add(button);
            x += button.Width + 6;
        }
    }

    // MARK: - 输入 / 附件

    private void WireInput()
    {
        _input.PasteImage += (_, _) =>
        {
            var image = Clipboard.GetImage();
            if (image is null) return;
            var png = ImageToPng(image);
            if (png is null) return;
            AddImageAttachment(png, "粘贴的图片");
        };
        _input.PasteFiles += (_, _) => HandleFiles(Clipboard.GetFileDropList().OfType<string>().ToArray());
        _input.TextChangedForHeight += (_, _) => UpdateCommandList();
        _input.TextChanged += (_, _) => UpdateCommandList();
        _input.Submit += (_, _) => send();
    }

    private void AddImageAttachment(byte[] data, string name)
    {
        if (!_imageSupported)
        {
            AddSystemMessage("当前 agent 未声明图片输入能力，无法发送图片。");
            return;
        }
        var block = new OutContent { type = "image", mimeType = "image/png", data = Convert.ToBase64String(data) };
        _attachments.Add(block);
        AddChip(name, () => _attachments.RemoveAll(a => ReferenceEquals(a, block)));
    }

    private void AddFileAttachment(string path)
    {
        var size = new FileInfo(path).Length;
        var mime = MimeFor(path);
        var name = Path.GetFileName(path);
        var uri = new Uri(path).AbsoluteUri;

        OutContent block;
        if (_embeddedContextSupported && size <= 1_000_000 && IsTextFile(path)
            && File.ReadAllText(path) is { Length: > 0 } text)
        {
            block = new OutContent
            {
                type = "resource",
                resource = new Dictionary<string, object?> { ["uri"] = uri, ["mimeType"] = mime, ["text"] = text },
            };
        }
        else
        {
            block = new OutContent { type = "resource_link", uri = uri, name = name, mimeType = mime, size = (int)size };
        }
        _attachments.Add(block);
        AddChip(name, () => _attachments.RemoveAll(a => ReferenceEquals(a, block)));
    }

    private void AddChip(string name, Action remove)
    {
        _attachmentPanel.Visible = true;
        var chip = new Panel { Width = 150, Height = 26, Margin = new Padding(0, 0, 6, 4), BackColor = Color.FromArgb(45, 45, 45) };
        var label = new Label { Text = name, AutoSize = false, Width = 112, Height = 22, Location = new Point(2, 2), TextAlign = ContentAlignment.MiddleLeft };
        var close = new Button { Text = "✕", Width = 20, Height = 20, Location = new Point(126, 2), FlatStyle = FlatStyle.Flat };
        close.FlatAppearance.BorderSize = 0;
        close.Click += (_, _) =>
        {
            remove();
            _attachmentPanel.Controls.Remove(chip);
            if (_attachments.Count == 0) _attachmentPanel.Visible = false;
        };
        chip.Controls.Add(label);
        chip.Controls.Add(close);
        _attachmentPanel.Controls.Add(chip);
    }

    private void HandleFiles(IReadOnlyList<string> paths)
    {
        foreach (var path in paths)
        {
            if (!File.Exists(path)) continue;
            var ext = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
            if (ext is "png" or "jpg" or "jpeg" or "gif" or "bmp" or "webp")
            {
                var data = File.ReadAllBytes(path);
                AddImageAttachment(data, Path.GetFileName(path));
            }
            else
            {
                AddFileAttachment(path);
            }
        }
    }

    private static bool IsTextFile(string path)
    {
        var ext = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
        return ext is "txt" or "md" or "json" or "yaml" or "yml" or "swift" or "cs" or "py" or "js" or "ts"
            or "html" or "css" or "xml" or "sh" or "sql" or "log" or "csv" or "toml" or "ini";
    }

    private static string? MimeFor(string path)
    {
        var ext = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
        return ext switch
        {
            "png" => "image/png",
            "jpg" or "jpeg" => "image/jpeg",
            "gif" => "image/gif",
            "webp" => "image/webp",
            "md" or "markdown" => "text/markdown",
            "json" => "application/json",
            "html" or "htm" => "text/html",
            "css" => "text/css",
            _ => null,
        };
    }

    private static byte[]? ImageToPng(Image image)
    {
        try
        {
            using var bitmap = new Bitmap(image);
            using var ms = new MemoryStream();
            bitmap.Save(ms, ImageFormat.Png);
            return ms.ToArray();
        }
        catch
        {
            return null;
        }
    }

    // MARK: - 命令联想

    private void UpdateCommandList()
    {
        var text = _input.Text;
        if (!text.StartsWith('/') || text.Contains(' ') || _commands.Count == 0)
        {
            _commandList.Visible = false;
            return;
        }
        var query = text[1..].ToLowerInvariant();
        var matches = _commands
            .Where(c => query.Length == 0 || c.Name.ToLowerInvariant().StartsWith(query))
            .Take(8)
            .ToList();
        if (matches.Count == 0)
        {
            _commandList.Visible = false;
            return;
        }

        _commandList.Items.Clear();
        foreach (var c in matches)
        {
            _commandList.Items.Add($"/{c.Name}  {c.Description}");
        }
        _commandList.Height = Math.Min(matches.Count * 22 + 4, 160);
        _commandList.Location = new Point(_inputPanel.Left + 8, Math.Max(0, _inputPanel.Top - _commandList.Height));
        _commandList.Visible = true;
    }

    // MARK: - 发送

    private void send()
    {
        if (!_connected) return;
        var text = _input.Text.Trim();
        if (text.Length == 0 && _attachments.Count == 0) return;

        var content = new List<object>();
        if (text.Length > 0) content.Add(new OutContent { type = "text", text = text });
        foreach (var block in _attachments) content.Add(block);

        AddUserMessage(text, ImageAttachments(), FileAttachmentNames());
        _attachments.Clear();
        _attachmentPanel.Controls.Clear();
        _attachmentPanel.Visible = false;
        _input.Clear();
        _streaming.Clear();

        _running = true;
        UpdateSendState();
        _cli.AgentPrompt(content);
    }

    private IReadOnlyList<byte[]> ImageAttachments() =>
        _attachments.Where(a => a.type == "image" && a.data is not null)
                    .Select(a => Convert.FromBase64String(a.data!))
                    .ToList();

    private IReadOnlyList<string> FileAttachmentNames() =>
        _attachments.Where(a => a.type != "image")
                    .Select(a => a.name ?? "file")
                    .ToList();

    private void UpdateSendState()
    {
        _sendButton.BackColor = _running
            ? Color.FromArgb(180, 80, 60)
            : model_canSend() ? Color.FromArgb(70, 110, 220) : Color.FromArgb(60, 60, 60);
    }

    private bool model_canSend() =>
        _connected && (_input.Text.Trim().Length > 0 || _attachments.Count > 0);

    // MARK: - 生命周期

    private void Ui(Action action)
    {
        if (IsHandleCreated)
        {
            try { BeginInvoke(action); } catch { }
        }
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        UpdateSendState();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        base.OnFormClosing(e);
    }
}
