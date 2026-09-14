namespace TokCat;

/// <summary>数值格式化，口径与 macOS 侧一致（单位 t / $）。</summary>
public static class Formatting
{
    public static string Units(double value, bool currency = false)
    {
        var sign = value < 0 ? "-" : string.Empty;
        var abs = Math.Abs(value);
        var (scaled, suffix) = abs switch
        {
            >= 1_000_000_000 => (abs / 1_000_000_000, "B"),
            >= 1_000_000 => (abs / 1_000_000, "M"),
            >= 1_000 => (abs / 1_000, "K"),
            _ => (abs, string.Empty),
        };
        var number = suffix.Length == 0 ? scaled.ToString("0.##") : scaled.ToString("0.##");
        return currency
            ? $"{sign}${number}{suffix}"
            : $"{sign}{number}{suffix} t";
    }

    public static string Rate(double value, bool currency)
        => currency ? $"{Units(value, true)}/s" : $"{Units(value)}/s";
}
