using System.Drawing;
using System.Windows.Forms;

namespace TokCat;

/// <summary>左键弹出的小状态窗：显示当前速率、合计与各来源计数。</summary>
public sealed class StatusForm : Form
{
    private readonly Label _rateLabel;
    private readonly Label _totalLabel;
    private readonly ListBox _sourceList;

    public StatusForm()
    {
        Text = "TokCat";
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        ClientSize = new Size(280, 190);
        Font = new Font("Segoe UI", 9f);

        var title = new Label
        {
            Text = "Token 消耗",
            AutoSize = true,
            Location = new Point(12, 10),
            Font = new Font("Segoe UI", 9f, FontStyle.Bold),
        };

        _rateLabel = new Label
        {
            Text = "—",
            AutoSize = true,
            Location = new Point(12, 34),
            Font = new Font("Segoe UI", 16f, FontStyle.Bold),
        };

        _totalLabel = new Label
        {
            Text = "合计 —",
            AutoSize = true,
            Location = new Point(12, 72),
            ForeColor = Color.DimGray,
        };

        _sourceList = new ListBox
        {
            Location = new Point(12, 96),
            Size = new Size(256, 84),
            BorderStyle = BorderStyle.FixedSingle,
        };

        Controls.Add(title);
        Controls.Add(_rateLabel);
        Controls.Add(_totalLabel);
        Controls.Add(_sourceList);
    }

    public void UpdateSnapshot(Snapshot snapshot)
    {
        _rateLabel.Text = Formatting.Rate(snapshot.Rate, snapshot.Currency);
        _totalLabel.Text = "合计 " + Formatting.Units(snapshot.TotalUnits, snapshot.Currency);

        var selected = _sourceList.SelectedIndex;
        _sourceList.BeginUpdate();
        _sourceList.Items.Clear();
        foreach (var source in snapshot.Sources)
        {
            var mark = source.Enabled ? "●" : "○";
            _sourceList.Items.Add($"{mark} {source.Name}");
        }
        _sourceList.EndUpdate();
        if (selected >= 0 && selected < _sourceList.Items.Count)
        {
            _sourceList.SelectedIndex = selected;
        }
    }
}
