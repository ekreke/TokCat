using System.Windows.Forms;

namespace TokCat;

/// <summary>
/// 多行输入框：拦截 WM_PASTE（图片/文件 → 附件事件），Enter 发送、Shift+Enter 换行。
/// </summary>
internal sealed class PasteAwareTextBox : TextBox
{
    private const int WmPaste = 0x0302;

    public event EventHandler? PasteImage;
    public event EventHandler? PasteFiles;
    public event EventHandler? Submit;

    public PasteAwareTextBox()
    {
        Multiline = true;
        BorderStyle = BorderStyle.None;
        ScrollBars = ScrollBars.Vertical;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmPaste)
        {
            if (Clipboard.ContainsImage())
            {
                PasteImage?.Invoke(this, EventArgs.Empty);
                return;
            }
            if (Clipboard.ContainsFileDropList())
            {
                PasteFiles?.Invoke(this, EventArgs.Empty);
                return;
            }
        }
        base.WndProc(ref m);
    }

    protected override bool IsInputKey(Keys keyData)
    {
        // 让 Enter 进入 OnKeyDown（否则多行 TextBox 会直接吃掉）。
        if ((keyData & Keys.KeyCode) == Keys.Enter) return true;
        return base.IsInputKey(keyData);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if ((e.KeyCode & Keys.KeyCode) == Keys.Enter && !e.Shift)
        {
            e.Handled = true;
            e.SuppressKeyPress = true;
            Submit?.Invoke(this, EventArgs.Empty);
            return;
        }
        base.OnKeyDown(e);
    }

    protected override void OnTextChanged(EventArgs e)
    {
        base.OnTextChanged(e);
        TextChangedForHeight?.Invoke(this, EventArgs.Empty);
    }

    internal event EventHandler? TextChangedForHeight;
}
