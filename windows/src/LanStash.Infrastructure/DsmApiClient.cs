using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Nodes;
using LanStash.Domain;

namespace LanStash.Infrastructure;

public sealed class DsmApiClient(HttpClient httpClient) : IDsmApiClient
{
    private readonly HttpClient _http = httpClient;

    public Uri GetBaseUri(NasProfile profile)
    {
        var input = profile.Host.Trim();
        if (!input.Contains("://", StringComparison.Ordinal))
        {
            input = $"https://{input}";
        }

        if (!Uri.TryCreate(input, UriKind.Absolute, out var uri) ||
            !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
            string.IsNullOrWhiteSpace(uri.Host))
        {
            throw new DsmException(
                UserText.Key("WinShared23ac67f1f673dd23"),
                UserText.Key("WinShareddcac071c2cf16346"));
        }

        var builder = new UriBuilder(uri);
        if (profile.Port is not null)
        {
            builder.Port = profile.Port.Value;
        }
        builder.Path = builder.Path.TrimEnd('/');
        return builder.Uri;
    }

    public async Task<IReadOnlyDictionary<string, ApiCapability>> DiscoverAsync(
        NasProfile profile,
        CancellationToken cancellationToken = default)
    {
        var data = await PostAsync(
            profile,
            "/webapi/query.cgi",
            new Dictionary<string, string>
            {
                ["api"] = "SYNO.API.Info",
                ["version"] = "1",
                ["method"] = "query",
                ["query"] = "all",
            },
            session: null,
            cancellationToken).ConfigureAwait(false);
        var result = new Dictionary<string, ApiCapability>(StringComparer.Ordinal);
        foreach (var (name, node) in data)
        {
            if (node is not JsonObject value ||
                value["path"]?.GetValue<string>() is not { Length: > 0 } path)
            {
                continue;
            }
            var minVersion = value["minVersion"]?.GetValue<int>() ?? 1;
            var maxVersion = value["maxVersion"]?.GetValue<int>() ?? minVersion;
            result[name] = new ApiCapability(
                name,
                path,
                minVersion,
                maxVersion,
                value["requestFormat"]?.GetValue<string>() ?? "FORM");
        }
        return result;
    }

    public async Task<DsmSession> LoginAsync(
        NasProfile profile,
        string password,
        string? otp,
        CancellationToken cancellationToken = default)
    {
        var parameters = new Dictionary<string, string>
        {
            ["api"] = "SYNO.API.Auth",
            ["version"] = "7",
            ["method"] = "login",
            ["account"] = profile.Username,
            ["passwd"] = password,
            ["session"] = "FileStation",
            ["format"] = "sid",
            ["enable_syno_token"] = "yes",
            ["enable_device_token"] = "yes",
            ["device_name"] = "LanStash Windows",
        };
        if (!string.IsNullOrWhiteSpace(otp))
        {
            parameters["otp_code"] = otp.Trim();
        }
        var data = await PostAsync(
            profile,
            "/webapi/auth.cgi",
            parameters,
            session: null,
            cancellationToken).ConfigureAwait(false);
        var sid = data["sid"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(sid))
        {
            throw new DsmException(
                UserText.Key("WinSharedab4ce8cd180797fc"),
                UserText.Key("WinSharedc144a2dc9ace5c1f"),
                authenticationFailure: true);
        }
        return new DsmSession(
            profile.Id,
            sid,
            data["synotoken"]?.GetValue<string>(),
            data["did"]?.GetValue<string>());
    }

    public async Task LogoutAsync(
        NasProfile profile,
        DsmSession session,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await PostAsync(
                profile,
                "/webapi/auth.cgi",
                new Dictionary<string, string>
                {
                    ["api"] = "SYNO.API.Auth",
                    ["version"] = "7",
                    ["method"] = "logout",
                    ["session"] = "FileStation",
                },
                session,
                cancellationToken).ConfigureAwait(false);
        }
        catch (DsmException)
        {
            // 本机仍应清除会话，远端退出失败不阻塞用户。
        }
    }

    public Task<JsonObject> CallAsync(
        NasProfile profile,
        DsmSession session,
        ApiCapability capability,
        string method,
        IReadOnlyDictionary<string, string>? parameters = null,
        CancellationToken cancellationToken = default)
    {
        var values = new Dictionary<string, string>
        {
            ["api"] = capability.Name,
            ["version"] = capability.MaxVersion.ToString(),
            ["method"] = method,
        };
        if (parameters is not null)
        {
            foreach (var (key, value) in parameters)
            {
                values[key] = value;
            }
        }
        var path = capability.Path.StartsWith('/') ? capability.Path : $"/webapi/{capability.Path}";
        return PostAsync(profile, path, values, session, cancellationToken);
    }

    public async Task<byte[]> ReadFileRangeAsync(
        NasProfile profile,
        DsmSession session,
        ApiCapability capability,
        string remotePath,
        long offset,
        long length,
        CancellationToken cancellationToken = default)
    {
        if (offset < 0 || length <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(offset));
        }
        var path = capability.Path.StartsWith('/')
            ? capability.Path
            : $"/webapi/{capability.Path}";
        var parameters = new Dictionary<string, string>
        {
            ["api"] = capability.Name,
            ["version"] = capability.MaxVersion.ToString(),
            ["method"] = "download",
            ["path"] = JsonSerializer.Serialize(new[] { remotePath }),
            ["mode"] = "download",
            ["_sid"] = session.Sid,
        };
        var query = string.Join(
            "&",
            parameters.Select(pair =>
                $"{Uri.EscapeDataString(pair.Key)}={Uri.EscapeDataString(pair.Value)}"));
        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            new Uri(GetBaseUri(profile), $"{path}?{query}"));
        request.Headers.Range = new RangeHeaderValue(offset, checked(offset + length - 1));
        request.Headers.UserAgent.ParseAdd("LanStash-Windows/0.1");
        if (!string.IsNullOrWhiteSpace(session.SynoToken))
        {
            request.Headers.TryAddWithoutValidation("X-SYNO-TOKEN", session.SynoToken);
        }
        using var response = await _http.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        await using var source = await response.Content.ReadAsStreamAsync(
            cancellationToken).ConfigureAwait(false);
        if (response.StatusCode != HttpStatusCode.PartialContent && offset > 0)
        {
            await SkipAsync(source, offset, cancellationToken).ConfigureAwait(false);
        }
        using var destination = new MemoryStream(
            checked((int)Math.Min(length, int.MaxValue)));
        var remaining = length;
        var buffer = new byte[1024 * 1024];
        while (remaining > 0)
        {
            var read = await source.ReadAsync(
                buffer.AsMemory(0, (int)Math.Min(buffer.Length, remaining)),
                cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                break;
            }
            await destination.WriteAsync(
                buffer.AsMemory(0, read),
                cancellationToken).ConfigureAwait(false);
            remaining -= read;
        }
        return destination.ToArray();
    }

    private static async Task SkipAsync(
        Stream stream,
        long byteCount,
        CancellationToken cancellationToken)
    {
        var buffer = new byte[1024 * 1024];
        var remaining = byteCount;
        while (remaining > 0)
        {
            var read = await stream.ReadAsync(
                buffer.AsMemory(0, (int)Math.Min(buffer.Length, remaining)),
                cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                throw new EndOfStreamException();
            }
            remaining -= read;
        }
    }

    private async Task<JsonObject> PostAsync(
        NasProfile profile,
        string path,
        IReadOnlyDictionary<string, string> parameters,
        DsmSession? session,
        CancellationToken cancellationToken)
    {
        var values = new Dictionary<string, string>(parameters, StringComparer.Ordinal);
        if (session is not null)
        {
            values["_sid"] = session.Sid;
        }
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            new Uri(GetBaseUri(profile), path))
        {
            Content = new FormUrlEncodedContent(values),
        };
        request.Headers.Accept.ParseAdd("application/json");
        request.Headers.UserAgent.ParseAdd("LanStash-Windows/0.1");
        if (session is not null)
        {
            request.Headers.TryAddWithoutValidation("Cookie", $"id={session.Sid}");
            if (!string.IsNullOrWhiteSpace(session.SynoToken))
            {
                request.Headers.TryAddWithoutValidation("X-SYNO-TOKEN", session.SynoToken);
            }
        }

        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new DsmException(
                UserText.Key("WinShared5a870c4775a4ef6b"),
                UserText.Key("WinShared199c5367bae9682d"));
        }
        catch (HttpRequestException)
        {
            throw new DsmException(
                UserText.Key("WinSharedf91eef8a1cf7b01c"),
                UserText.Key("WinShared79c4d60046afa3ff"));
        }
        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new DsmException(
                    UserText.Key("WinSharedf91eef8a1cf7b01c"),
                    UserText.Key("WinShared79c4d60046afa3ff"),
                    (int)response.StatusCode,
                    response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden);
            }
            await using var stream = await response.Content
                .ReadAsStreamAsync(cancellationToken)
                .ConfigureAwait(false);
            var envelope = await JsonNode.ParseAsync(
                stream,
                cancellationToken: cancellationToken).ConfigureAwait(false) as JsonObject
                ?? throw new DsmException(
                    UserText.Key("WinShared9cb9ec075b03b6cb"),
                    UserText.Key("WinShared09f262a53ad074ca"));
            if (envelope["success"]?.GetValue<bool>() == true)
            {
                return envelope["data"] as JsonObject ?? [];
            }
            var code = envelope["error"]?["code"]?.GetValue<int>();
            throw MapFailure(code);
        }
    }

    private static DsmException MapFailure(int? code) => code switch
    {
        102 => new(UserText.Key("WinShared11a208e43c34b77c"), UserText.Key("WinShared371d84f48836296f"), code),
        103 => new(UserText.Key("WinShared189ee06b7da78f3f"), UserText.Key("WinSharedb5641013fbf13d8b"), code),
        104 => new(UserText.Key("WinSharedd727aa9e0a8cff65"), UserText.Key("WinSharedc144a2dc9ace5c1f"), code, true),
        105 => new(UserText.Key("WinShared12188668a1d4cff1"), UserText.Key("WinShared4a1330714c58b25d"), code),
        406 => new(UserText.Key("WinShared3cd43f3a371513e2"), UserText.Key("WinShared46e3e4901826eb40"), code, true),
        407 => new(UserText.Key("WinSharedef0eed96e1f28ed8"), UserText.Key("WinShared2ad42c7573d49cbc"), code, true),
        400 or 401 or 402 or 403 or 404 =>
            new(UserText.Key("WinShared78eee40d2f30576e"), UserText.Key("WinShared2f7ffa8e29481728"), code, true),
        _ => new(UserText.Key("WinShared0addf7c060c570ce"), UserText.Key("WinShared5448ceb91a80e260"), code),
    };
}
