using System.Text.Json.Nodes;
using LanStash.Domain;
using LanStash.Infrastructure;

namespace LanStash.Tests;

public sealed class DeleteRequestContractTests
{
    [Fact]
    public async Task FileStationDeleteMatchesSharedRequestFixture()
    {
        var fixture = RequestFixture.Load("FileStationDelete.json");
        var api = new RecordingApiClient();
        var repository = CreateRepository(
            api,
            fixture.Capability,
            new ApiCapability("SYNO.FileStation.List", "entry.cgi", 2, 2, "FORM"));

        await repository.DeleteFilesAsync(["<synthetic-path>"]);

        var request = api.Single(fixture.ApiName, fixture.Method);
        fixture.AssertRequest(request);
        var paths = JsonNode.Parse(request.Parameters["path"])!.AsArray();
        var path = Assert.Single(paths);
        Assert.Equal("<synthetic-path>", path!.GetValue<string>());
        Assert.Equal("true", request.Parameters["recursive"]);
        Assert.Equal("true", request.Parameters["accurate_progress"]);
    }

    [Fact]
    public async Task ContainerDeleteOnlySendsContractIdentifier()
    {
        var fixture = RequestFixture.Load("ContainerDelete.json");
        var api = new RecordingApiClient();
        var repository = CreateRepository(api, fixture.Capability);

        await repository.DeleteContainerAsync("<synthetic-container>");

        var request = api.Single(fixture.ApiName, fixture.Method);
        fixture.AssertRequest(request);
        Assert.Equal("<synthetic-container>", request.Parameters["id"]);
    }

    [Fact]
    public async Task OfficialVirtualMachineDeleteOnlySendsGuestIdentifier()
    {
        var fixture = RequestFixture.Load("VirtualMachineDelete.json");
        var api = new RecordingApiClient();
        var repository = CreateRepository(api, fixture.Capability);

        await repository.DeleteVirtualMachineAsync("<synthetic-virtual-machine>");

        var request = api.Single(fixture.ApiName, fixture.Method);
        fixture.AssertRequest(request);
        Assert.Equal("<synthetic-virtual-machine>", request.Parameters["guest_id"]);
        Assert.DoesNotContain("id", request.Parameters.Keys);
        Assert.DoesNotContain("network_id", request.Parameters.Keys);
        Assert.DoesNotContain("image_id", request.Parameters.Keys);
    }

    [Fact]
    public async Task LegacyVirtualMachineDeleteKeepsItsCompatibilityIdentifiers()
    {
        var capability = new ApiCapability(
            "SYNO.Virtualization.Guest",
            "entry.cgi",
            1,
            2,
            "FORM");
        var api = new RecordingApiClient();
        var repository = CreateRepository(api, capability);

        await repository.DeleteVirtualMachineAsync("legacy-guest");

        var request = api.Single(capability.Name, "delete");
        Assert.Equal(
            new[] { "guest_id", "id" },
            request.Parameters.Keys.Order(StringComparer.Ordinal));
        Assert.All(request.Parameters.Values, value => Assert.Equal("legacy-guest", value));
        Assert.DoesNotContain("network_id", request.Parameters.Keys);
        Assert.DoesNotContain("image_id", request.Parameters.Keys);
    }

    private static DsmRepository CreateRepository(
        RecordingApiClient api,
        params ApiCapability[] capabilities)
    {
        var profileId = Guid.Parse("11111111-1111-1111-1111-111111111111");
        return new DsmRepository(
            new NasProfile(profileId, "测试 NAS", "nas.invalid", 5001, "tester"),
            new DsmSession(profileId, "synthetic-sid", null, null),
            api,
            capabilities.ToDictionary(item => item.Name, StringComparer.Ordinal));
    }
}

internal sealed record RecordedApiRequest(
    ApiCapability Capability,
    string Method,
    IReadOnlyDictionary<string, string> Parameters);

internal sealed class RecordingApiClient : IDsmApiClient
{
    private readonly List<RecordedApiRequest> _requests = [];

    public RecordedApiRequest Single(string apiName, string method) =>
        Assert.Single(_requests, item =>
            item.Capability.Name == apiName && item.Method == method);

    public Task<JsonObject> CallAsync(
        NasProfile profile,
        DsmSession session,
        ApiCapability capability,
        string method,
        IReadOnlyDictionary<string, string>? parameters = null,
        CancellationToken cancellationToken = default)
    {
        _requests.Add(new RecordedApiRequest(
            capability,
            method,
            new Dictionary<string, string>(
                parameters ?? new Dictionary<string, string>(),
                StringComparer.Ordinal)));
        return Task.FromResult(new JsonObject());
    }

    public Uri GetBaseUri(NasProfile profile) => new("https://nas.invalid");

    public Task<IReadOnlyDictionary<string, ApiCapability>> DiscoverAsync(
        NasProfile profile,
        CancellationToken cancellationToken = default) =>
        throw new NotSupportedException();

    public Task<DsmSession> LoginAsync(
        NasProfile profile,
        string password,
        string? otp,
        CancellationToken cancellationToken = default) =>
        throw new NotSupportedException();

    public Task LogoutAsync(
        NasProfile profile,
        DsmSession session,
        CancellationToken cancellationToken = default) =>
        throw new NotSupportedException();

    public Task<byte[]> ReadFileRangeAsync(
        NasProfile profile,
        DsmSession session,
        ApiCapability capability,
        string remotePath,
        long offset,
        long length,
        CancellationToken cancellationToken = default) =>
        throw new NotSupportedException();
}

internal sealed record RequestFixture(
    string ApiName,
    string Method,
    int Version,
    string Path,
    IReadOnlySet<string> ParameterNames)
{
    public ApiCapability Capability => new(ApiName, Path, Version, Version, "FORM");

    public static RequestFixture Load(string fileName)
    {
        var path = System.IO.Path.Combine(
            AppContext.BaseDirectory,
            "RequestFixtures",
            fileName);
        var root = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        var api = root["api"]!.AsObject();
        var parameterNames = root["parameters"]!.AsArray()
            .Select(item => item!["name"]!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);
        return new RequestFixture(
            api["name"]!.GetValue<string>(),
            api["method"]!.GetValue<string>(),
            api["resolvedVersion"]!.GetValue<int>(),
            api["resolvedPath"]!.GetValue<string>(),
            parameterNames);
    }

    public void AssertRequest(RecordedApiRequest request)
    {
        Assert.Equal(ApiName, request.Capability.Name);
        Assert.Equal(Method, request.Method);
        Assert.Equal(Version, request.Capability.MaxVersion);
        Assert.Equal(Path, request.Capability.Path);
        Assert.Equal(
            ParameterNames.Order(StringComparer.Ordinal),
            request.Parameters.Keys.Order(StringComparer.Ordinal));
    }
}
