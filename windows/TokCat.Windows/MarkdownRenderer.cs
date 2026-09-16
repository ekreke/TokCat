using System.Text;
using System.Text.RegularExpressions;
using Markdig;
using ColorCode;

namespace TokCat;

/// <summary>Markdown → HTML（代码块用 ColorCode 做语法高亮）。</summary>
internal static class MarkdownRenderer
{
    private static readonly MarkdownPipeline Pipeline = new MarkdownPipelineBuilder()
        .UseAdvancedExtensions()
        .Build();

    private static readonly Regex CodeBlockRegex = new(
        "<pre><code(?: class=\"language-(?<lang>[\\w#+.-]+))?\">(?<code>[\\s\\S]*?)</code></pre>",
        RegexOptions.Compiled);

    public static string ToHtml(string? markdown)
    {
        if (string.IsNullOrWhiteSpace(markdown)) return string.Empty;
        try
        {
            var html = Markdown.ToHtml(markdown, Pipeline);
            return Highlight(html);
        }
        catch
        {
            return "<pre>" + System.Net.WebUtility.HtmlEncode(markdown) + "</pre>";
        }
    }

    /// <summary>对 <c>&lt;pre&gt;&lt;code&gt;</c> 块做语法高亮；失败时保持原样。</summary>
    private static string Highlight(string html)
    {
        try
        {
            return CodeBlockRegex.Replace(html, match =>
            {
                var lang = match.Groups["lang"].Value;
                var code = System.Net.WebUtility.HtmlDecode(match.Groups["code"].Value);
                try
                {
                    var language = string.IsNullOrWhiteSpace(lang)
                        ? null
                        : Languages.FindById(lang);
                    if (language is null)
                    {
                        return "<pre><code>" + System.Net.WebUtility.HtmlEncode(code) + "</code></pre>";
                    }
                    var sb = new StringBuilder();
                    new HtmlFormatter().WriteHtml(code, language, t => sb.Append(t));
                    return sb.ToString();
                }
                catch
                {
                    return "<pre><code>" + System.Net.WebUtility.HtmlEncode(code) + "</code></pre>";
                }
            });
        }
        catch
        {
            return html;
        }
    }
}
