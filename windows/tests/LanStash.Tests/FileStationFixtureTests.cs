using System.Text.Json.Nodes;
using LanStash.Infrastructure;

namespace LanStash.Tests;

public sealed class FileStationFixtureTests
{
    [Fact]
    public void SharedFixturesHandleStringNumbersAndMalformedAdditionalData()
    {
        var stringNumbers = Parse("synthetic-string-numbers");
        Assert.Equal(2, stringNumbers.Total);
        Assert.Equal(2, stringNumbers.Items.Count);
        Assert.Equal(5, stringNumbers.Items[0].Size);
        Assert.Equal(
            DateTimeOffset.FromUnixTimeSeconds(1_700_000_000),
            stringNumbers.Items[0].ModifiedAt);

        var missingAdditional = Parse("synthetic-missing-additional");
        Assert.Single(missingAdditional.Items);
        Assert.False(missingAdditional.Items[0].IsDirectory);

        var malformedAdditional = Parse("synthetic-malformed-additional");
        Assert.Equal(2, malformedAdditional.Items.Count);
    }

    private static LanStash.Domain.FilePage Parse(string fixtureId)
    {
        var path = Path.Combine(
            AppContext.BaseDirectory,
            "Fixtures",
            fixtureId,
            "response.json");
        var envelope = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        var data = envelope["data"]!.AsObject();
        return DsmFixtureParser.ParseFilePage(data);
    }
}
