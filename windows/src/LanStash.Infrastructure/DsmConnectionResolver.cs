using LanStash.Domain;

namespace LanStash.Infrastructure;

public sealed record DiscoveredConnection(
    NasProfile Profile,
    IReadOnlyDictionary<string, ApiCapability> Capabilities);

/// <summary>
/// 登录前只使用不含凭据的能力发现探测连接候选。
/// 找到可信连接后，调用方才可以提交账号、密码和验证码。
/// </summary>
public sealed class DsmConnectionResolver(
    IDsmApiClient api,
    DsmQuickConnectResolver quickConnect)
{
    public async Task<DiscoveredConnection> DiscoverAsync(
        NasProfile profile,
        Action<string>? updateStatus = null,
        CancellationToken cancellationToken = default)
    {
        var parsed = NasAddressParser.Parse(profile.Host, profile.Port);
        if (parsed.Kind == NasAddressKind.Direct)
        {
            updateStatus?.Invoke("正在连接 NAS…");
            var directProfile = profile with { Host = parsed.Host, Port = parsed.Port };
            return new(
                directProfile,
                await api.DiscoverAsync(directProfile, cancellationToken));
        }

        updateStatus?.Invoke("正在通过 QuickConnect 查找 NAS…");
        IReadOnlyList<QuickConnectEndpoint> endpoints;
        try
        {
            endpoints = await quickConnect.ResolveAsync(parsed.Host, cancellationToken);
        }
        catch (DsmException error) when (error.Message == "QuickConnect 没有提供可用的直接连接")
        {
            endpoints = [];
        }

        DsmException? lastDirectError = null;
        foreach (var endpoint in endpoints)
        {
            updateStatus?.Invoke(endpoint.Kind == QuickConnectEndpointKind.Local
                ? "正在尝试局域网连接…"
                : "正在尝试外网直接连接…");
            var connectionProfile = profile with
            {
                Host = endpoint.Host,
                Port = profile.Port ?? endpoint.Port,
            };
            try
            {
                return new(
                    connectionProfile,
                    await api.DiscoverAsync(connectionProfile, cancellationToken));
            }
            catch (DsmException error)
            {
                lastDirectError = error;
            }
        }

        updateStatus?.Invoke("正在建立 QuickConnect 安全中继…");
        try
        {
            var relay = await quickConnect.RequestRelayAsync(parsed.Host, cancellationToken);
            var relayProfile = profile with { Host = relay.Host, Port = relay.Port };
            return new(
                relayProfile,
                await api.DiscoverAsync(relayProfile, cancellationToken));
        }
        catch (DsmException error) when (
            error.Message == "QuickConnect 暂时无法建立中继连接" && lastDirectError is not null)
        {
            throw lastDirectError;
        }
    }
}
