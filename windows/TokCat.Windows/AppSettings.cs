using System.Text.Json;
using System.Text.Json.Serialization;

namespace TokCat;

/// <summary>用户偏好，持久化到 %APPDATA%\TokCat\settings.json。</summary>
public sealed class AppSettings
{
    public string MetricKind { get; set; } = "weighted";
    public double IconSize { get; set; } = 20;
    public double MaxFps { get; set; } = 24;
    public double Sensitivity { get; set; } = 1.0;
    public double SaturationRate { get; set; } = 300;
    public double IdleFps { get; set; } = 2;
    public Dictionary<string, bool> SourceOverrides { get; set; } = new();

    [JsonIgnore]
    public static string Directory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TokCat");

    [JsonIgnore]
    private static string FilePath => Path.Combine(Directory, "settings.json");

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var json = File.ReadAllText(FilePath);
                var loaded = JsonSerializer.Deserialize<AppSettings>(json, Options);
                if (loaded is not null) return loaded;
            }
        }
        catch
        {
            // 配置损坏时回退默认值。
        }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Options));
        }
        catch
        {
            // 忽略写入失败。
        }
    }

    public bool IsEnabled(string sourceId, bool defaultEnabled)
        => SourceOverrides.TryGetValue(sourceId, out var v) ? v : defaultEnabled;

    public void SetEnabled(string sourceId, bool enabled)
    {
        SourceOverrides[sourceId] = enabled;
        Save();
    }
}
