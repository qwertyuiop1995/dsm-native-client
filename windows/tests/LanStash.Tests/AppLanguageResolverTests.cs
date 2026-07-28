using LanStash.Domain;

namespace LanStash.Tests;

public sealed class AppLanguageResolverTests
{
    [Theory]
    [InlineData("en-GB", "en-US")]
    [InlineData("zh-Hans-CN", "zh-CN")]
    [InlineData("zh-CN", "zh-CN")]
    [InlineData("zh-SG", "zh-CN")]
    [InlineData("zh-Hant-TW", "en-US")]
    [InlineData("ja-JP", "en-US")]
    [InlineData(null, "en-US")]
    public void SystemLanguageUsesEnglishFallback(string? systemLanguage, string expected) =>
        Assert.Equal(expected, AppLanguageResolver.ResolveSystemLanguage(systemLanguage));

    [Fact]
    public void ExplicitLanguageOverridesSystem()
    {
        Assert.Equal(
            "zh-CN",
            AppLanguageResolver.Resolve(
                AppLanguageSelection.SimplifiedChinese,
                "ja-JP"));
    }
}
