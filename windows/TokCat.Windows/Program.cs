using System.Windows.Forms;

namespace TokCat;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        try { Payload.EnsureExtracted(); } catch { /* 解压失败时仍尝试运行 */ }
        using var context = new TrayApplicationContext();
        Application.Run(context);
    }
}
