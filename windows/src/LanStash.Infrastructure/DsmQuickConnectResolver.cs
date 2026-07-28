using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using LanStash.Domain;

namespace LanStash.Infrastructure;

public enum QuickConnectEndpointKind
{
    Local,
    External,
    Relay,
}

public sealed record QuickConnectEndpoint(string Host, int Port, QuickConnectEndpointKind Kind);

/// <summary>
/// 受限使用 Synology QuickConnect 当前客户端契约。
/// get_server_info、request_tunnel 属于未公开的内部 API；登录前会限制官方域名并验证中继身份。
/// </summary>
public sealed class DsmQuickConnectResolver(HttpClient httpClient)
{
    private const int MaximumResponseBytes = 1024 * 1024;
    private readonly HttpClient _http = httpClient;
    private static readonly string[] ControlUrls =
    [
        "https://global.quickconnect.to/Serv.php",
        "https://global.quickconnect.cn/Serv.php",
    ];

    public async Task<IReadOnlyList<QuickConnectEndpoint>> ResolveAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        ValidateId(id);
        DsmException? lastError = null;
        foreach (var controlUrl in ControlUrls)
        {
            try
            {
                return DecodeEndpoints(await SendAsync(
                    "get_server_info", false, id, controlUrl, cancellationToken).ConfigureAwait(false));
            }
            catch (DsmException error)
            {
                lastError = error;
            }
        }
        throw lastError ?? ServiceUnavailable();
    }

    public async Task<QuickConnectEndpoint> RequestRelayAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        ValidateId(id);
        var controlUrl = await ResolveControlUrlAsync(id, cancellationToken).ConfigureAwait(false);
        DsmException? lastError = null;
        for (var attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                var descriptor = DecodeRelayDescriptor(await SendAsync(
                    "request_tunnel", true, id, controlUrl, cancellationToken).ConfigureAwait(false), id);
                await VerifyRelayAsync(descriptor, cancellationToken).ConfigureAwait(false);
                return descriptor.Endpoint;
            }
            catch (DsmException error) when (
                error.Message is not "这台 NAS 没有开启 QuickConnect 中继" and
                not "QuickConnect 返回的连接无法确认属于这台 NAS")
            {
                lastError = error;
                if (attempt < 2)
                {
                    await Task.Delay((attempt + 1) * 1000, cancellationToken).ConfigureAwait(false);
                }
            }
        }
        throw lastError ?? RelayUnavailable();
    }

    public static IReadOnlyList<QuickConnectEndpoint> DecodeEndpoints(JsonArray responses)
    {
        var response = SuccessfulResponse(responses);
        if (!string.Equals(response["server"]?["ds_state"]?.GetValue<string>(), "CONNECTED",
                StringComparison.OrdinalIgnoreCase))
        {
            throw new DsmException(
                "QuickConnect 找到了这台 NAS，但设备目前不在线",
                "确认 NAS 已开机并联网后重试。");
        }
        var port = response["service"]?["port"]?.GetValue<int>() ?? 0;
        var smartDns = response["smartdns"] as JsonObject;
        if (port is < 1 or > 65535 || smartDns is null)
        {
            throw NoDirectRoute();
        }

        var endpoints = new List<QuickConnectEndpoint>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (smartDns["lan"] is JsonArray lan)
        {
            foreach (var value in lan)
            {
                var host = value is JsonObject item
                    ? item["host"]?.GetValue<string>()
                    : value?.GetValue<string>();
                AddTrustedDirect(endpoints, seen, host, port, QuickConnectEndpointKind.Local);
            }
        }
        AddTrustedDirect(
            endpoints,
            seen,
            smartDns["host"]?.GetValue<string>(),
            port,
            QuickConnectEndpointKind.External);
        return endpoints.Count > 0 ? endpoints : throw NoDirectRoute();
    }

    private async Task<string> ResolveControlUrlAsync(string id, CancellationToken cancellationToken)
    {
        DsmException? lastError = null;
        foreach (var controlUrl in ControlUrls)
        {
            try
            {
                var response = SuccessfulResponse(await SendAsync(
                    "get_server_info", false, id, controlUrl, cancellationToken).ConfigureAwait(false));
                var host = response["env"]?["control_host"]?.GetValue<string>()?.ToLowerInvariant();
                if (host is null || !IsTrustedControlHost(host))
                {
                    throw InvalidResponse();
                }
                return $"https://{host}/Serv.php";
            }
            catch (DsmException error)
            {
                lastError = error;
            }
        }
        throw lastError ?? ServiceUnavailable();
    }

    private async Task<JsonArray> SendAsync(
        string command,
        bool stopWhenSuccess,
        string serverId,
        string controlUrl,
        CancellationToken cancellationToken)
    {
        var payload = new JsonArray
        {
            new JsonObject
            {
                ["version"] = 1,
                ["command"] = command,
                ["stop_when_error"] = false,
                ["stop_when_success"] = stopWhenSuccess,
                ["id"] = "mainapp_https",
                ["serverID"] = serverId,
                ["is_gofile"] = false,
                ["path"] = "",
            },
        };
        using var request = new HttpRequestMessage(HttpMethod.Post, controlUrl)
        {
            Content = new StringContent(payload.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        request.Headers.Accept.ParseAdd("application/json");
        request.Headers.UserAgent.ParseAdd("LanStash-Windows/0.1");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(command == "request_tunnel" ? TimeSpan.FromSeconds(30) : TimeSpan.FromSeconds(15));
        try
        {
            using var response = await _http.SendAsync(
                request, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                throw ServiceUnavailable();
            }
            return await ReadJsonArrayAsync(response, timeout.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw ServiceUnavailable();
        }
        catch (HttpRequestException)
        {
            throw ServiceUnavailable();
        }
    }

    private async Task VerifyRelayAsync(RelayDescriptor descriptor, CancellationToken cancellationToken)
    {
        if (!descriptor.PingPongPath.StartsWith('/') ||
            descriptor.PingPongPath.Length > 2048 ||
            descriptor.PingPongPath.Contains("://", StringComparison.Ordinal) ||
            descriptor.PingPongPath.Contains('#'))
        {
            throw InvalidResponse();
        }
        var expectedId = Convert.ToHexString(
            MD5.HashData(Encoding.UTF8.GetBytes(descriptor.ServerId))).ToLowerInvariant();
        var uri = new Uri($"https://{descriptor.Endpoint.Host}{descriptor.PingPongPath}");
        for (var attempt = 0; attempt < 6; attempt++)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, uri);
                request.Headers.Accept.ParseAdd("application/json");
                request.Headers.UserAgent.ParseAdd("LanStash-Windows/0.1");
                using var response = await _http.SendAsync(
                    request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
                if (!response.IsSuccessStatusCode)
                {
                    throw RelayUnavailable();
                }
                var json = await ReadJsonObjectAsync(response, cancellationToken).ConfigureAwait(false);
                if (!string.Equals(json["ezid"]?.GetValue<string>(), expectedId, StringComparison.OrdinalIgnoreCase))
                {
                    throw new DsmException(
                        "QuickConnect 返回的连接无法确认属于这台 NAS",
                        "为保护登录信息，岚仓已停止连接。");
                }
                return;
            }
            catch (DsmException error) when (
                error.Message != "QuickConnect 返回的连接无法确认属于这台 NAS" && attempt < 5)
            {
                await Task.Delay(1000, cancellationToken).ConfigureAwait(false);
            }
            catch (HttpRequestException) when (attempt < 5)
            {
                await Task.Delay(1000, cancellationToken).ConfigureAwait(false);
            }
        }
        throw RelayUnavailable();
    }

    private static RelayDescriptor DecodeRelayDescriptor(JsonArray responses, string id)
    {
        if (responses.OfType<JsonObject>().Any(item => item["errno"]?.GetValue<int>() == 19))
        {
            throw new DsmException(
                "这台 NAS 没有开启 QuickConnect 中继",
                "请在 DSM 的 QuickConnect 高级设置中开启中继后重试。");
        }
        var response = SuccessfulResponse(responses);
        var service = response["service"] as JsonObject;
        var server = response["server"] as JsonObject;
        var environment = response["env"] as JsonObject;
        var relayPort = service?["relay_port"]?.GetValue<int>() ?? 0;
        var serverId = server?["serverID"]?.GetValue<string>();
        var region = environment?["relay_region"]?.GetValue<string>()?.ToLowerInvariant();
        var controlHost = environment?["control_host"]?.GetValue<string>()?.ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(service?["relay_ip"]?.GetValue<string>()) ||
            relayPort is < 1 or > 65535 ||
            string.IsNullOrWhiteSpace(serverId) ||
            region is null || !IsValidHostLabel(region) ||
            controlHost is null || !IsTrustedControlHost(controlHost))
        {
            throw RelayUnavailable();
        }
        var topDomain = controlHost.EndsWith(".quickconnect.cn", StringComparison.Ordinal) ? "cn" : "to";
        var host = $"{id.ToLowerInvariant()}.{region}.quickconnect.{topDomain}";
        if (!IsTrustedRelayHost(host))
        {
            throw InvalidResponse();
        }
        return new(
            new QuickConnectEndpoint(host, 443, QuickConnectEndpointKind.Relay),
            serverId,
            server?["pingpong_path"]?.GetValue<string>()
                ?? "/webman/pingpong.cgi?action=cors&quickconnect=true");
    }

    public static bool IsTrustedRelayHost(string host)
    {
        var labels = host.ToLowerInvariant().Split('.');
        return labels.Length == 4 &&
            labels[2] == "quickconnect" &&
            labels[3] is "to" or "cn" &&
            IsValidHostLabel(labels[0]) &&
            IsValidHostLabel(labels[1]);
    }

    private static JsonObject SuccessfulResponse(JsonArray responses) =>
        responses.OfType<JsonObject>().FirstOrDefault(item => item["errno"]?.GetValue<int>() == 0)
        ?? throw new DsmException(
            "没有找到这个 QuickConnect ID",
            "请检查拼写和 NAS 中的 QuickConnect 设置。");

    private static void AddTrustedDirect(
        ICollection<QuickConnectEndpoint> endpoints,
        ISet<string> seen,
        string? rawHost,
        int port,
        QuickConnectEndpointKind kind)
    {
        var host = rawHost?.ToLowerInvariant();
        if (host is not null && IsTrustedDirectHost(host) && seen.Add(host))
        {
            endpoints.Add(new(host, port, kind));
        }
    }

    private static bool IsTrustedDirectHost(string host)
    {
        var labels = host.Split('.');
        return labels.Length >= 4 &&
            labels[^3] == "direct" &&
            labels[^2] == "quickconnect" &&
            labels[^1] is "to" or "cn" &&
            labels.All(IsValidHostLabel);
    }

    private static bool IsTrustedControlHost(string host) =>
        (host.EndsWith(".quickconnect.to", StringComparison.Ordinal) ||
         host.EndsWith(".quickconnect.cn", StringComparison.Ordinal)) &&
        host.Split('.').All(IsValidHostLabel);

    private static bool IsValidHostLabel(string value) =>
        value.Length is >= 1 and <= 63 &&
        value[0] != '-' &&
        value[^1] != '-' &&
        value.All(character =>
            character is >= 'a' and <= 'z' or >= 'A' and <= 'Z' or >= '0' and <= '9' or '-');

    private static void ValidateId(string id)
    {
        if (!NasAddressParser.IsPotentialQuickConnectId(id))
        {
            throw new DsmException("无法识别这个 QuickConnect ID", "请检查拼写后重试。");
        }
    }

    private static async Task<JsonArray> ReadJsonArrayAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        var node = await ReadJsonAsync(response, cancellationToken).ConfigureAwait(false);
        return node as JsonArray ?? throw InvalidResponse();
    }

    private static async Task<JsonObject> ReadJsonObjectAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        var node = await ReadJsonAsync(response, cancellationToken).ConfigureAwait(false);
        return node as JsonObject ?? throw RelayUnavailable();
    }

    private static async Task<JsonNode?> ReadJsonAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        if (response.Content.Headers.ContentLength > MaximumResponseBytes)
        {
            throw InvalidResponse();
        }
        await using var source = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        using var memory = new MemoryStream();
        var buffer = new byte[8192];
        while (true)
        {
            var count = await source.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            if (count == 0)
            {
                break;
            }
            if (memory.Length + count > MaximumResponseBytes)
            {
                throw InvalidResponse();
            }
            await memory.WriteAsync(buffer.AsMemory(0, count), cancellationToken).ConfigureAwait(false);
        }
        memory.Position = 0;
        return await JsonNode.ParseAsync(memory, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    private static DsmException NoDirectRoute() => new(
        "QuickConnect 没有提供可用的直接连接",
        "岚仓将继续尝试安全中继。");
    private static DsmException ServiceUnavailable() => new(
        "QuickConnect 暂时没有响应",
        "请稍后重试。");
    private static DsmException InvalidResponse() => new(
        "QuickConnect 返回的信息无法读取",
        "请稍后重试。");
    private static DsmException RelayUnavailable() => new(
        "QuickConnect 暂时无法建立中继连接",
        "请稍后重试。");

    private sealed record RelayDescriptor(
        QuickConnectEndpoint Endpoint,
        string ServerId,
        string PingPongPath);
}
