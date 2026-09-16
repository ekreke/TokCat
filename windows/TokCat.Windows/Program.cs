using System.Threading;
using System.Windows.Forms;

namespace TokCat;

internal static class Program
{
    private const string MutexName = "TokCat.SingleInstance.Mutex";
    private const string ActivateEventName = "TokCat.SingleInstance.Activate";

    private static Mutex? _mutex;

    [STAThread]
    private static void Main()
    {
        // 单实例：第二个实例只负责「通知已有实例激活窗口」，然后退出，
        // 避免重复托盘图标与多个 TokCatCli.exe 子进程。
        bool createdNew;
        _mutex = new Mutex(initiallyOwned: true, name: MutexName, out createdNew);
        if (!createdNew)
        {
            try
            {
                if (EventWaitHandle.TryOpenExisting(ActivateEventName, out var handle))
                {
                    handle.Set();
                    handle.Dispose();
                }
            }
            catch
            {
                // 忽略：无法通知就直接退出。
            }
            return;
        }

        ApplicationConfiguration.Initialize();
        try { Payload.EnsureExtracted(); } catch { /* 解压失败时仍尝试运行 */ }
        using var context = new TrayApplicationContext();
        Application.Run(context);

        GC.KeepAlive(_mutex);
        _mutex.ReleaseMutex();
        _mutex.Dispose();
    }
}
