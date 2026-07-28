using LanStash.Domain;
using LanStash.Infrastructure;
using System.Text.Json.Nodes;

namespace LanStash.Tests;

public sealed class DsmApiClientTests
{
    private readonly DsmApiClient _client = new(new HttpClient());

    [Fact]
    public void AddressWithoutSchemeUsesHttps()
    {
        var uri = _client.GetBaseUri(Profile("nas.example.com"));

        Assert.Equal("https", uri.Scheme);
        Assert.Equal("nas.example.com", uri.Host);
    }

    [Fact]
    public void ExplicitPortOverridesAddressPort()
    {
        var uri = _client.GetBaseUri(Profile("https://nas.example.com:5001/dsm/", 8443));

        Assert.Equal(8443, uri.Port);
        Assert.Equal("/dsm", uri.AbsolutePath);
    }

    [Theory]
    [InlineData("http://nas.example.com")]
    [InlineData("https://")]
    [InlineData("")]
    public void UnsafeOrIncompleteAddressIsRejected(string address)
    {
        Assert.Throws<DsmException>(() => _client.GetBaseUri(Profile(address)));
    }

    [Fact]
    public void CapabilityVersionStaysInsideSupportedRange()
    {
        var capability = new ApiCapability("test", "entry.cgi", 2, 5, "FORM");

        Assert.Equal(2, capability.SelectVersion(1));
        Assert.Equal(4, capability.SelectVersion(4));
        Assert.Equal(5, capability.SelectVersion(9));
    }

    [Fact]
    public void DownloadProgressIsBounded()
    {
        var task = new DownloadTask(
            "1",
            "示例",
            "downloading",
            100,
            120,
            0,
            0,
            null,
            null);

        Assert.Equal(1, task.Progress);
    }

    [Fact]
    public void ExistingSavedProfileWithoutAutoLoginRemainsCompatible()
    {
        const string json =
            """
            {
              "Id": "4fcb8ec9-cd91-45c6-a234-9f47b67fc560",
              "DisplayName": "测试 NAS",
              "Host": "nas.example.com",
              "Port": null,
              "Username": "tester",
              "RememberSession": true
            }
            """;

        var profile = System.Text.Json.JsonSerializer.Deserialize<NasProfile>(json);

        Assert.NotNull(profile);
        Assert.False(profile.AutoLogin);
        Assert.True(profile.RememberSession);
    }

    [Theory]
    [InlineData("my-nas", "my-nas")]
    [InlineData("https://quickconnect.to/my-nas", "my-nas")]
    [InlineData("my-nas.quickconnect.to", "my-nas")]
    public void QuickConnectAddressIsRecognized(string input, string expectedId)
    {
        var address = NasAddressParser.Parse(input);

        Assert.Equal(NasAddressKind.QuickConnect, address.Kind);
        Assert.Equal(expectedId, address.Host);
        Assert.Equal(5001, address.Port);
    }

    [Fact]
    public void QuickConnectResponseOnlyAcceptsOfficialDirectHosts()
    {
        var response = JsonNode.Parse(
            """
            [{
              "errno": 0,
              "server": {"ds_state": "CONNECTED"},
              "service": {"port": 5001},
              "smartdns": {
                "lan": [
                  {"host": "192-168-1-20.my-nas.direct.quickconnect.to"},
                  {"host": "attacker.example"}
                ],
                "host": "my-nas.direct.quickconnect.to"
              }
            }]
            """)!.AsArray();

        var endpoints = DsmQuickConnectResolver.DecodeEndpoints(response);

        Assert.Equal(2, endpoints.Count);
        Assert.All(endpoints, endpoint =>
            Assert.EndsWith(".direct.quickconnect.to", endpoint.Host, StringComparison.Ordinal));
    }

    [Fact]
    public void QuickConnectResponseRejectsUntrustedHosts()
    {
        var response = JsonNode.Parse(
            """
            [{
              "errno": 0,
              "server": {"ds_state": "CONNECTED"},
              "service": {"port": 5001},
              "smartdns": {"lan": [{"host": "attacker.example"}]}
            }]
            """)!.AsArray();

        Assert.Throws<DsmException>(() => DsmQuickConnectResolver.DecodeEndpoints(response));
    }

    [Fact]
    public async Task OptionalRealQuickConnectDiscoveryDoesNotSendCredentials()
    {
        var id = Environment.GetEnvironmentVariable("LANSTASH_QUICKCONNECT_TEST_ID");
        if (string.IsNullOrWhiteSpace(id))
        {
            return;
        }
        using var http = new HttpClient(new HttpClientHandler { AllowAutoRedirect = false })
        {
            Timeout = TimeSpan.FromSeconds(45),
        };
        var api = new DsmApiClient(http);
        var resolver = new DsmConnectionResolver(api, new DsmQuickConnectResolver(http));
        var profile = new NasProfile(
            Guid.NewGuid(),
            "QuickConnect 只读探测",
            id,
            null,
            "unused");

        var connection = await resolver.DiscoverAsync(profile);

        Assert.Contains("SYNO.API.Auth", connection.Capabilities.Keys);
        Assert.True(
            connection.Profile.Host.EndsWith(".direct.quickconnect.to", StringComparison.Ordinal) ||
            connection.Profile.Host.EndsWith(".direct.quickconnect.cn", StringComparison.Ordinal) ||
            DsmQuickConnectResolver.IsTrustedRelayHost(connection.Profile.Host));
    }

    private static NasProfile Profile(string host, int? port = null) =>
        new(Guid.Parse("4fcb8ec9-cd91-45c6-a234-9f47b67fc560"), "测试 NAS", host, port, "tester");
}
