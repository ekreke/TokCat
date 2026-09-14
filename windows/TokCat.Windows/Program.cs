using System.Windows.Forms;

namespace TokCat;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        using var context = new TrayApplicationContext();
        Application.Run(context);
    }
}
