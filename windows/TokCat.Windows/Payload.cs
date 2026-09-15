namespace TokCat;

/// <summary>
/// 把内嵌的 Swift 引擎与猫精灵自解压到 %LOCALAPPDATA%\TokCat，
/// 使发布物是一个单文件 TokCat.exe。
/// </summary>
internal static class Payload
{
    private static readonly string[] CatFrames =
        { "cat_0.png", "cat_1.png", "cat_2.png", "cat_3.png", "cat_4.png" };

    public static string Root { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TokCat");

    public static string CliExe => Path.Combine(Root, "TokCatCli.exe");

    public static string AssetsDir => Path.Combine(Root, "Assets", "RunCatCat");

    /// <summary>版本一致且已解压时跳过；否则重写。</summary>
    public static void EnsureExtracted()
    {
        var version = typeof(Payload).Assembly.GetName().Version?.ToString() ?? "0";
        var marker = Path.Combine(Root, ".payload");
        if (File.Exists(marker) && File.Exists(CliExe)
            && File.ReadAllText(marker).Trim() == version)
        {
            return;
        }

        Directory.CreateDirectory(Root);
        Directory.CreateDirectory(AssetsDir);

        ExtractResource("TokCatCli.exe", CliExe);

        // Swift 运行时 DLL（Windows 不支持完全静态链接）：与 CLI 同目录，系统可自动加载。
        foreach (var name in typeof(Payload).Assembly.GetManifestResourceNames())
        {
            if (name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
            {
                ExtractResource(name, Path.Combine(Root, name));
            }
        }

        foreach (var frame in CatFrames)
        {
            ExtractResource(frame, Path.Combine(AssetsDir, frame));
        }

        File.WriteAllText(marker, version);
    }

    private static void ExtractResource(string name, string destination)
    {
        using var stream = typeof(Payload).Assembly.GetManifestResourceStream(name);
        if (stream is null) return;

        var tmp = destination + ".tmp";
        using (var file = File.Create(tmp)) stream.CopyTo(file);
        if (File.Exists(destination)) File.Delete(destination);
        File.Move(tmp, destination);
    }
}
