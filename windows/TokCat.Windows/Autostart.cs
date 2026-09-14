using Microsoft.Win32;

namespace TokCat;

/// <summary>开机自启（HKCU Run 键；MSIX 形态下可后续改用 StartupTask）。</summary>
internal static class Autostart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "TokCat";

    private static string ExecutablePath =>
        Environment.ProcessPath ?? Application.ExecutablePath;

    public static bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
        var value = key?.GetValue(ValueName) as string;
        return !string.IsNullOrEmpty(value);
    }

    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)
                        ?? Registry.CurrentUser.CreateSubKey(RunKey);
        if (key is null) return;

        if (enabled)
        {
            key.SetValue(ValueName, $"\"{ExecutablePath}\"");
        }
        else
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }
}
