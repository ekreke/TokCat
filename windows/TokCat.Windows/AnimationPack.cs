using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace TokCat;

/// <summary>
/// 动画包：加载 PNG 序列，按最近邻缩放，并用指定颜色重绘（单色模板），
/// 缓存每种 (帧, 尺寸, 颜色) 的 Icon，避免高频切换时产生 GDI 句柄泄漏。
/// </summary>
public sealed class AnimationPack : IDisposable
{
    private readonly List<Bitmap> _frames = new();
    private readonly Dictionary<string, Icon> _icons = new();

    public int FrameCount => _frames.Count;
    public double IdleFps { get; private set; } = 2;
    public double DefaultMaxFps { get; private set; } = 24;

    public AnimationPack()
    {
        var dir = Path.Combine(AppContext.BaseDirectory, "Assets", "RunCatCat");
        if (!Directory.Exists(dir)) return;
        var files = Directory.GetFiles(dir, "cat_*.png");
        Array.Sort(files, StringComparer.Ordinal);
        foreach (var file in files)
        {
            try { _frames.Add(new Bitmap(file)); }
            catch { /* 跳过损坏素材 */ }
        }
    }

    public Icon? GetFrame(int index, int size, Color color)
    {
        if (_frames.Count == 0) return null;
        size = Math.Max(8, size);
        var i = ((index % _frames.Count) + _frames.Count) % _frames.Count;
        var key = $"{i}:{size}:{color.ToArgb():X8}";
        if (_icons.TryGetValue(key, out var cached)) return cached;
        var icon = Render(_frames[i], size, color);
        if (icon is not null) _icons[key] = icon;
        return icon;
    }

    private static Icon? Render(Bitmap source, int size, Color color)
    {
        var ratio = (double)source.Width / source.Height;
        var w = Math.Max(1, (int)Math.Round(size * ratio));
        var h = Math.Max(1, size);

        using var canvas = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(canvas))
        {
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            g.Clear(Color.Transparent);
        }

        // 源图当作 alpha 掩码，用指定颜色重绘。
        for (var y = 0; y < h; y++)
        {
            for (var x = 0; x < w; x++)
            {
                var sx = x * source.Width / w;
                var sy = y * source.Height / h;
                var p = source.GetPixel(sx, sy);
                if (p.A < 8) continue;
                canvas.SetPixel(x, y, Color.FromArgb(p.A, color));
            }
        }

        var hicon = canvas.GetHicon();
        try
        {
            using var tmp = Icon.FromHandle(hicon);
            return (Icon)tmp.Clone();
        }
        finally
        {
            DestroyIcon(hicon);
        }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr handle);

    public void Dispose()
    {
        foreach (var icon in _icons.Values) icon.Dispose();
        _icons.Clear();
        foreach (var frame in _frames) frame.Dispose();
        _frames.Clear();
    }
}
