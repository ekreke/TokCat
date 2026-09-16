using System.Text.RegularExpressions;
using Markdig;

namespace TokCat;

/// <summary>Markdown → HTML（代码块用 WebView 内的 CSS 样式呈现）。</summary>
internal static class MarkdownRenderer
{
    private static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder()
        .UseAdvancedExtensions()
        .Build();

    public static string ToHtml(string? markdown)
    {
        if (string.IsNullOrWhiteSpace(markdown)) return string.Empty;
        try
        {
            return Markdown.ToHtml(markdown, Pipeline);
        }
        catch
        {
            return "<pre>" + System.Net.WebUtility.HtmlEncode(markdown) + "</pre>";
        }
    }
}
